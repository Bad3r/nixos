# Copyright (c) 2026 Bad3r

"""mitmproxy addon: Mendel flags, server <guidelines>, and streaming passthrough.

Rewrites responses only (requests, headers, and all other endpoints pass untouched):
  - /v1alpha:fetchConfig               (experimentConfig.experimentFlags[])
  - /v1internal:listExperiments        (flags[])
  - /v1internal:fetchAvailableModels   (template__system_prompts__guidelines)

With guidelines_pin set, a fetchAvailableModels response is replaced by an HTTP 502
before any override is applied, whatever guidelines_override is, when Google's
guidelines template differs from the pinned sha256, when the key is malformed, moved,
or (with a replacement file) absent, when any other server template__* override
appears, or when the check itself fails. Unpinned templates are saved to
guidelines_drift_dir for review; a failed save still blocks the response.

Streaming responses (Connect / gRPC-web / SSE) are passed through unbuffered so
long-lived RPC streams do not stall; set stream_tap_log to record frames to JSONL.

When ca_bundle_out or spki_out is set, running() writes the combined system + proxy
CA bundle and the base64 SHA-256 SPKI pin atomically before sending sd_notify READY=1.
"""

from __future__ import annotations

import base64
import codecs
import hashlib
import json
import logging
import math
import os
import socket
import time
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Iterator

try:
    from mitmproxy import ctx, http
except ImportError:  # Allow standalone offline unit tests with python3 -I
    ctx: Any = None
    http: Any = None

LOG = logging.getLogger("proxy_overrides")

FLAG_PATHS: dict[str, tuple[str | None, str]] = {
    "/v1alpha:fetchConfig": ("experimentConfig", "experimentFlags"),
    "/v1internal:listExperiments": (None, "flags"),
}
MODELS_PATH = "/v1internal:fetchAvailableModels"
GUIDELINES_KEY = "template__system_prompts__guidelines"
TEMPLATE_PREFIX = "template__"
STREAM_TYPES = ("application/connect+", "application/grpc", "text/event-stream")
SHA256_HEX_LEN = 64
HEX_CHARS = frozenset("0123456789abcdef")
CONNECT_FRAME_HEADER_LEN = 5
CONNECT_EOS_FLAG = 0x02
HTTP_OK = 200
HTTP_BAD_GATEWAY = 502


def _expand_opt(raw: str) -> str:
    """Strip and expand a path option string, preserving empty values."""
    cleaned = raw.strip()
    return str(Path(cleaned).expanduser()) if cleaned else ""


def parse_flag_overrides(spec: str) -> dict[str, tuple[str, object, str]]:
    """Parse a JSON object of flag name to bool, int, float, or string into an override map.

    Each entry maps to (proto_field_name, typed_value, string_form); rewrite_flags sends
    string_form when the server already carries the flag as stringValue.
    """
    if not spec.strip():
        return {}
    data = json.loads(spec)
    if not isinstance(data, dict):
        msg = "flag_overrides must be a JSON object"
        raise ValueError(msg)  # noqa: TRY004
    overrides: dict[str, tuple[str, object, str]] = {}
    for name, value in data.items():
        if isinstance(value, bool):
            overrides[name] = ("boolValue", value, json.dumps(value))
        elif isinstance(value, int):
            overrides[name] = ("intValue", str(value), str(value))  # proto3 int64 is a JSON string
        elif isinstance(value, float):
            if not math.isfinite(value):
                msg = f"flag_overrides[{name!r}] is not a finite number"
                raise ValueError(msg)
            overrides[name] = ("floatValue", value, json.dumps(value))
        elif isinstance(value, str):
            overrides[name] = ("stringValue", value, value)
        else:
            msg = f"flag_overrides[{name!r}] has unsupported type {type(value).__name__}"
            raise ValueError(msg)  # noqa: TRY004
    return overrides


def rewrite_flags(
    body: dict[str, Any],
    path: str,
    overrides: dict[str, tuple[str, object, str]],
) -> list[str]:
    """Apply Mendel flag overrides in-place on fetchConfig / listExperiments bodies."""
    target = FLAG_PATHS.get(path)
    if not target or not overrides or not isinstance(body, dict):
        return []
    holder = body.setdefault(target[0], {}) if target[0] else body
    if not isinstance(holder, dict):
        return []
    flags = holder.setdefault(target[1], [])
    if not isinstance(flags, list):
        return []

    changed: list[str] = []
    for name, (kind, value, raw) in overrides.items():
        entry = next((f for f in flags if isinstance(f, dict) and f.get("name") == name), None)
        if entry is None:
            entry = {"name": name}
            flags.append(entry)
        server_kind = next((k for k in entry if k.endswith("Value")), None)
        for k in [k for k in entry if k.endswith("Value")]:
            del entry[k]
        if server_kind == "stringValue" and kind != "stringValue":
            entry["stringValue"] = raw
        else:
            entry[kind] = value
        changed.append(name)
    return changed


def _iter_experiment_dicts(body: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any]]]:
    """Yield (container_label, experiments_dict) pairs inside fetchAvailableModels JSON."""
    models = body.get("models")
    if isinstance(models, dict):
        for model_id, model_cfg in models.items():
            if not isinstance(model_cfg, dict):
                continue
            model_exp = model_cfg.get("modelExperiments")
            if not isinstance(model_exp, dict):
                continue
            experiments = model_exp.get("experiments")
            if isinstance(experiments, dict):
                yield f"models.{model_id}", experiments

    shared = body.get("sharedModelExperiments")
    if isinstance(shared, dict):
        for group_id, group_cfg in shared.items():
            if not isinstance(group_cfg, dict):
                continue
            experiments = group_cfg.get("experiments")
            if isinstance(experiments, dict):
                yield f"sharedModelExperiments.{group_id}", experiments


def rewrite_guidelines(
    body: dict[str, Any],
    mode: str,
    template_text: str | None = None,
) -> list[str]:
    """Strip or replace template__system_prompts__guidelines in fetchAvailableModels."""
    if not mode or not isinstance(body, dict):
        return []
    if mode != "strip" and template_text is None:
        msg = "template_text is required when mode is not 'strip'"
        raise ValueError(msg)

    touched: list[str] = []
    for label, experiments in _iter_experiment_dicts(body):
        if GUIDELINES_KEY not in experiments:
            continue
        if mode == "strip":
            del experiments[GUIDELINES_KEY]
        else:
            experiments[GUIDELINES_KEY] = {"stringValue": template_text}
        touched.append(label)
    return touched


def read_pin(path: str) -> str:
    """Return the sha256 hex digest in PATH (first field, sha256sum format)."""
    fields = Path(path).read_text(encoding="utf-8").split()
    digest = fields[0].lower() if fields else ""
    if len(digest) != SHA256_HEX_LEN or any(c not in HEX_CHARS for c in digest):
        msg = f"{path}: first field is not a sha256 hex digest"
        raise ValueError(msg)
    return digest


def _template_refs(node: object, path: str = "$") -> Iterator[str]:
    """Yield JSON paths of every template__* key or string value anywhere in NODE."""
    if isinstance(node, dict):
        for key, value in node.items():
            sub = f"{path}.{key}"
            if isinstance(key, str) and key.startswith(TEMPLATE_PREFIX):
                yield sub
            yield from _template_refs(value, sub)
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from _template_refs(value, f"{path}[{i}]")
    elif isinstance(node, str) and node.startswith(TEMPLATE_PREFIX):
        yield f"{path}={node}"


def check_guidelines(
    body: object,
    pin: str,
    mode: str,
) -> tuple[list[str], dict[str, str], int]:
    """Compare server template overrides in a fetchAvailableModels body to PIN.

    Returns (problems, unpinned, found): unpinned maps the sha256 of each
    guidelines value that differs from PIN to its text; found counts entries
    carrying GUIDELINES_KEY. Any problem means the response must not reach the client.
    """
    if not isinstance(body, dict):
        return ["response body is not a JSON object"], {}, 0
    problems: list[str] = []
    unpinned: dict[str, str] = {}
    known: set[str] = set()
    found = 0
    for label, experiments in _iter_experiment_dicts(body):
        if label.startswith("models."):
            base = f"$.models.{label.removeprefix('models.')}.modelExperiments.experiments"
        else:
            base = f"$.{label}.experiments"
        if GUIDELINES_KEY not in experiments:
            continue
        known.add(f"{base}.{GUIDELINES_KEY}")
        found += 1
        value = experiments[GUIDELINES_KEY]
        text = value.get("stringValue") if isinstance(value, dict) else None
        if (
            not isinstance(value, dict)
            or set(value) != {"stringValue"}
            or not isinstance(text, str)
        ):
            problems.append(f"{label}: {GUIDELINES_KEY} is not a lone stringValue")
            continue
        digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
        if digest != pin:
            unpinned[digest] = text
            problems.append(f"{label}: guidelines sha256 {digest[:12]} != pinned {pin[:12]}")
    problems.extend(
        f"unpinned server template reference at {ref}"
        for ref in _template_refs(body)
        if ref not in known and not any(ref.startswith(f"{k}.") for k in known)
    )
    if found == 0 and mode not in {"", "strip"}:
        problems.append(
            f"no {GUIDELINES_KEY} in response; the replacement file would not be applied"
        )
    return problems, unpinned, found


def compute_spki_pin(cert_pem: bytes) -> str:
    """Compute the base64-encoded SHA-256 SubjectPublicKeyInfo pin for a PEM certificate."""
    from cryptography import x509  # noqa: PLC0415
    from cryptography.hazmat.primitives import serialization  # noqa: PLC0415

    cert = x509.load_pem_x509_certificate(cert_pem)
    der = cert.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return base64.b64encode(hashlib.sha256(der).digest()).decode("ascii")


def _write_private_atomic(dest: Path, data: bytes) -> None:
    """Write DATA to DEST atomically with mode 0600."""
    dest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = dest.with_name(f".{dest.name}.tmp.{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        tmp.replace(dest)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def _sd_notify_ready() -> None:
    """Notify systemd that the proxy has finished startup when NOTIFY_SOCKET is set."""
    addr = os.environ.get("NOTIFY_SOCKET")
    if not addr:
        return
    target = f"\0{addr[1:]}" if addr.startswith("@") else addr
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
        sock.sendto(b"READY=1", target)


class DevModeOverrides:
    """Mitmproxy addon implementing Mendel flag and server guidelines overrides."""

    def __init__(self) -> None:
        """Initialize addon runtime state."""
        self.overrides: dict[str, tuple[str, object, str]] = {}
        self.guidelines_mode: str = ""
        self.guidelines_pin: str = ""
        self.guidelines_pin_error: str = ""
        self.flag_overrides_error: str = ""
        self.guidelines_drift_dir: str = ""
        self.ca_bundle_out: str = ""
        self.spki_out: str = ""
        self.system_ca_bundle: str = ""
        self.logged: set[str] = set()
        self.stream_bufs: dict[str, bytearray] = {}
        self.stream_pending: dict[str, bytearray] = {}
        self.stream_log: Any = None
        self.stream_log_path: str = ""

    def load(self, loader: Any) -> None:  # noqa: ANN401
        """Register mitmproxy addon options."""
        loader.add_option(
            "flag_overrides",
            str,
            "",
            "JSON object mapping Mendel flag names to bool, int, float, or string values",
        )
        loader.add_option(
            "guidelines_override",
            str,
            "",
            "Override server template__system_prompts__guidelines ('strip', path to .tmpl file, "
            "or empty to pass it through)",
        )
        loader.add_option(
            "guidelines_pin",
            str,
            "",
            "File whose first field is the sha256 of the expected server guidelines template; "
            "when set, fetchAvailableModels fails with HTTP 502 on any template drift",
        )
        loader.add_option(
            "guidelines_drift_dir",
            str,
            "",
            "Directory to save server guidelines templates that do not match guidelines_pin",
        )
        loader.add_option(
            "stream_tap_log",
            str,
            "",
            "Optional JSONL file to log streamed Connect/gRPC/SSE frames",
        )
        loader.add_option(
            "ca_bundle_out",
            str,
            "",
            "Optional path to write system CA bundle concatenated with mitmproxy's CA cert",
        )
        loader.add_option(
            "spki_out",
            str,
            "",
            "Optional path to write base64 SHA-256 SPKI pin of mitmproxy's CA cert",
        )
        loader.add_option(
            "system_ca_bundle",
            str,
            "/etc/ssl/certs/ca-certificates.crt",
            "System CA bundle concatenated ahead of mitmproxy's CA cert when writing ca_bundle_out",
        )

    def _close_stream_log(self) -> None:
        if self.stream_log is not None:
            self.stream_log.close()
            self.stream_log = None

    def _configure_flags(self) -> None:
        """Parse flag_overrides, recording a parse error for running() to fail startup on."""
        self.flag_overrides_error = ""
        try:
            self.overrides = parse_flag_overrides(ctx.options.flag_overrides)
        except ValueError as exc:
            self.overrides = {}
            self.flag_overrides_error = f"invalid flag_overrides: {exc}"
            LOG.error("proxy_overrides: %s", self.flag_overrides_error)  # noqa: TRY400
            return
        if self.overrides:
            summary = {k: {v[0]: v[1]} for k, v in self.overrides.items()}
            LOG.info("proxy_overrides: flags=%s", summary)

    def configure(self, updated: set[str]) -> None:
        """Apply updated mitmproxy option values."""
        if ctx is None:
            return
        self._configure_flags()
        self.guidelines_mode = ctx.options.guidelines_override.strip()
        self.guidelines_drift_dir = _expand_opt(ctx.options.guidelines_drift_dir)
        self.ca_bundle_out = _expand_opt(ctx.options.ca_bundle_out)
        self.spki_out = _expand_opt(ctx.options.spki_out)
        self.system_ca_bundle = _expand_opt(ctx.options.system_ca_bundle)
        self.guidelines_pin = ""
        self.guidelines_pin_error = ""
        pin_path = _expand_opt(ctx.options.guidelines_pin)
        if pin_path:
            try:
                self.guidelines_pin = read_pin(pin_path)
            except (OSError, ValueError) as exc:
                self.guidelines_pin_error = f"cannot read guidelines_pin: {exc}"
                LOG.error(  # noqa: TRY400
                    "proxy_overrides: GUIDELINES CHECK FAILED: %s",
                    self.guidelines_pin_error,
                )
        self.logged = set()
        if "stream_tap_log" in updated:
            new_path = _expand_opt(ctx.options.stream_tap_log)
            if new_path != self.stream_log_path:
                self._close_stream_log()
                self.stream_log_path = new_path
                if new_path:
                    self.stream_log = Path(new_path).open(  # noqa: SIM115
                        "a", buffering=1, encoding="utf-8"
                    )
        if self.guidelines_mode:
            LOG.info("proxy_overrides: guidelines=%s", self.guidelines_mode)
        if self.guidelines_pin:
            LOG.info("proxy_overrides: guidelines_pin=%s", self.guidelines_pin[:12])

    def running(self) -> None:
        """Publish CA artifacts and signal systemd readiness once the listener is up."""
        if ctx is None:
            return
        try:
            if self.flag_overrides_error:
                raise ValueError(self.flag_overrides_error)  # noqa: TRY301
            if self.guidelines_drift_dir:
                Path(self.guidelines_drift_dir).mkdir(parents=True, exist_ok=True, mode=0o700)
            if self.ca_bundle_out or self.spki_out:
                ca_dir = Path(ctx.options.confdir).expanduser()
                ca_cert_bytes = (ca_dir / "mitmproxy-ca-cert.pem").read_bytes()
                if self.ca_bundle_out:
                    sys_ca_bytes = Path(self.system_ca_bundle).read_bytes()
                    sep = b"" if sys_ca_bytes.endswith(b"\n") else b"\n"
                    _write_private_atomic(
                        Path(self.ca_bundle_out),
                        sys_ca_bytes + sep + ca_cert_bytes,
                    )
                if self.spki_out:
                    spki = compute_spki_pin(ca_cert_bytes)
                    _write_private_atomic(Path(self.spki_out), f"{spki}\n".encode("ascii"))
            _sd_notify_ready()
        except Exception as exc:  # noqa: BLE001
            LOG.error("proxy_overrides: startup failed: %s", exc)  # noqa: TRY400
            ctx.master.shutdown()

    def _emit_stream(self, flow: Any, kind: str, **fields: object) -> None:  # noqa: ANN401
        if self.stream_log is not None:
            rec: dict[str, object] = {
                "t": time.time(),
                "flow": flow.id,
                "path": flow.request.path,
                "kind": kind,
                **fields,
            }
            self.stream_log.write(json.dumps(rec) + "\n")

    def responseheaders(self, flow: Any) -> None:  # noqa: ANN401
        """Enable unbuffered streaming passthrough on Connect / gRPC / SSE responses."""
        path = flow.request.path.split("?")[0]
        if path in FLAG_PATHS or path == MODELS_PATH:
            return
        if flow.response is None:
            return
        ctype = flow.response.headers.get("content-type", "")
        if not ctype.startswith(STREAM_TYPES):
            return
        if self.stream_log is None:
            flow.response.stream = True
            return

        fid = flow.id
        self.stream_bufs[fid] = bytearray()
        self.stream_pending[fid] = bytearray()
        is_connect = ctype.startswith(("application/connect+", "application/grpc"))
        is_json = "json" in ctype
        # SSE text can split a UTF-8 sequence across chunks; decode incrementally.
        text_decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self._emit_stream(flow, "open", content_type=ctype, status=flow.response.status_code)

        def tap(chunk: bytes) -> bytes:
            self.stream_bufs[fid] += chunk
            if not is_connect:
                text = text_decoder.decode(chunk, final=not chunk)
                self._emit_stream(flow, "chunk", text=text)
                return chunk
            pend = self.stream_pending[fid]
            pend += chunk
            while len(pend) >= CONNECT_FRAME_HEADER_LEN:
                flags = pend[0]
                size = int.from_bytes(pend[1:CONNECT_FRAME_HEADER_LEN], "big")
                frame_end = CONNECT_FRAME_HEADER_LEN + size
                if len(pend) < frame_end:
                    break
                payload = bytes(pend[CONNECT_FRAME_HEADER_LEN:frame_end])
                del pend[:frame_end]
                frame: dict[str, object] = {"flags": flags, "size": size}
                if is_json or flags & CONNECT_EOS_FLAG:
                    frame["json"] = payload.decode("utf-8", "replace")
                else:
                    frame["b64"] = base64.b64encode(payload).decode()
                self._emit_stream(flow, "frame", **frame)
            return chunk

        flow.response.stream = tap

    def _handle_flags(self, flow: Any, path: str) -> None:  # noqa: ANN401
        if not self.overrides:
            return
        try:
            body = json.loads(flow.response.get_text())
        except ValueError:
            return
        changed = rewrite_flags(body, path, self.overrides)
        if not changed:
            return
        flow.response.set_text(json.dumps(body))
        flow.metadata["flag_overrides"] = changed
        if path not in self.logged:
            self.logged.add(path)
            if ctx is not None:
                LOG.info("proxy_overrides: rewrote %s on %s", ", ".join(changed), path)

    def _save_drift(self, unpinned: dict[str, str]) -> list[str]:
        """Save each unpinned template once; raise OSError when one cannot be saved."""
        saved: list[str] = []
        if not self.guidelines_drift_dir:
            return saved
        drift_dir = Path(self.guidelines_drift_dir)
        drift_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        for digest, text in unpinned.items():
            dest = drift_dir / f"server-guidelines.{digest[:12]}.tmpl"
            try:
                fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            except FileExistsError:
                saved.append(str(dest))
                continue
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as fh:
                    fh.write(text)
            except BaseException:
                # A partial file would be reported as saved on the next drift.
                dest.unlink(missing_ok=True)
                raise
            saved.append(str(dest))
        return saved

    def _block_models(self, flow: Any, problems: list[str]) -> None:  # noqa: ANN401
        """Replace fetchAvailableModels with HTTP 502 so drifted templates are blocked."""
        message = "antigravity-proxy blocked fetchAvailableModels: " + "; ".join(problems)
        error = {"error": {"code": HTTP_BAD_GATEWAY, "status": "UNAVAILABLE", "message": message}}
        flow.response = http.Response.make(
            HTTP_BAD_GATEWAY,
            json.dumps(error),
            {"content-type": "application/json"},
        )
        flow.metadata["guidelines_check"] = problems
        if ctx is not None:
            for problem in problems:
                LOG.error("proxy_overrides: GUIDELINES CHECK FAILED: %s", problem)

    def _load_replacement_template(self, *, checking: bool, flow: Any) -> tuple[bool, str | None]:  # noqa: ANN401
        if self.guidelines_mode in {"", "strip"}:
            return True, None
        try:
            return True, Path(self.guidelines_mode).read_text(encoding="utf-8")
        except OSError as exc:
            if checking:
                self._block_models(flow, [f"cannot read guidelines file: {exc}"])
            elif ctx is not None:
                LOG.error(  # noqa: TRY400
                    "proxy_overrides: cannot read guidelines file %s: %s",
                    self.guidelines_mode,
                    exc,
                )
            return False, None

    def _verify_guidelines(self, flow: Any, body: object, path: str) -> bool:  # noqa: ANN401
        problems, unpinned, found = check_guidelines(
            body, self.guidelines_pin, self.guidelines_mode
        )
        if problems:
            try:
                saved = self._save_drift(unpinned)
            except OSError as exc:
                problems.append(f"cannot save server template: {exc}")
            else:
                if saved:
                    problems.append("server template saved to " + ", ".join(saved))
            self._block_models(flow, problems)
            return False
        if found == 0 and "guidelines-absent" not in self.logged:
            self.logged.add("guidelines-absent")
            if ctx is not None:
                LOG.warning(
                    "proxy_overrides: %s absent from %s",
                    GUIDELINES_KEY,
                    path,
                )
        return True

    @property
    def _checking(self) -> bool:
        return bool(self.guidelines_pin or self.guidelines_pin_error)

    def _handle_models(self, flow: Any, path: str) -> None:  # noqa: ANN401
        """Run the guidelines check and override, blocking on any error while checking."""
        try:
            self._handle_guidelines(flow, path)
        except Exception as exc:
            # mitmproxy logs addon errors and forwards the unmodified response.
            if not self._checking:
                raise
            self._block_models(flow, [f"guidelines check failed: {type(exc).__name__}: {exc}"])

    def _handle_guidelines(self, flow: Any, path: str) -> None:  # noqa: ANN401
        checking = self._checking
        if not self.guidelines_mode and not checking:
            return
        if self.guidelines_pin_error:
            self._block_models(flow, [self.guidelines_pin_error])
            return
        ok, template_text = self._load_replacement_template(checking=checking, flow=flow)
        if not ok:
            return
        try:
            body = json.loads(flow.response.get_text())
        except ValueError:
            if checking:
                self._block_models(flow, ["response body is not JSON"])
            return
        if checking and not self._verify_guidelines(flow, body, path):
            return
        touched = rewrite_guidelines(body, self.guidelines_mode, template_text)
        if not touched:
            return
        flow.response.set_text(json.dumps(body))
        flow.metadata["guidelines_override"] = {
            "mode": self.guidelines_mode,
            "targets": touched,
        }
        if path not in self.logged:
            self.logged.add(path)
            if ctx is not None:
                LOG.info(
                    "proxy_overrides: guidelines (%s) applied to %d entries on %s",
                    self.guidelines_mode,
                    len(touched),
                    path,
                )

    def _finish_stream(self, flow: Any, kind: str, **fields: object) -> bool:  # noqa: ANN401
        buf = self.stream_bufs.pop(flow.id, None)
        self.stream_pending.pop(flow.id, None)
        if buf is None:
            return False
        if flow.response is not None:
            # Streamed chunks are the wire bytes (still Content-Encoding encoded).
            flow.response.raw_content = bytes(buf)
        self._emit_stream(flow, kind, total=len(buf), **fields)
        return True

    def response(self, flow: Any) -> None:  # noqa: ANN401
        """Apply flag or guidelines overrides to matching HTTP 200 responses."""
        if self._finish_stream(flow, "close"):
            return

        if flow.response is None or flow.response.status_code != HTTP_OK:
            return
        path = flow.request.path.split("?")[0]
        if path in FLAG_PATHS:
            self._handle_flags(flow, path)
        elif path == MODELS_PATH:
            self._handle_models(flow, path)

    def error(self, flow: Any) -> None:  # noqa: ANN401
        """Finalize stream state when an active stream aborts."""
        msg = flow.error.msg if flow.error is not None else ""
        self._finish_stream(flow, "error", error=msg)

    def done(self) -> None:
        """Close the optional stream tap log on shutdown."""
        self._close_stream_log()


addons = [DevModeOverrides()]
