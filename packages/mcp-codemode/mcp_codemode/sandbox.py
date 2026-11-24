# Copyright (c) 2026 Bad3r

"""Sandboxed JavaScript/TypeScript execution via Bubblewrap and Node 24 permissions."""

from __future__ import annotations

import contextlib
import json
import os
import signal
import subprocess
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from pathlib import Path

DEFAULT_EXEC_TIMEOUT_SEC = 120.0
MAX_TEXT_CHARS = 24_000
TRUNCATION_MARKER = "\n--- TRUNCATED ---"
NODE_MAX_HEAP_MB = 256
KILL_GRACE_SEC = 1.0
SANDBOX_TMP_MOUNT = "/tmp"  # noqa: S108


class SandboxError(RuntimeError):
    """Raised when the JS sandbox fails to start, times out, or throws."""

    @classmethod
    def startup_failed(cls, detail: str) -> SandboxError:
        """Create an error when the sandbox process cannot start."""
        return cls(f"codemode sandbox failed to start: {detail}")

    @classmethod
    def missing_bwrap(cls) -> SandboxError:
        """Create an error when Bubblewrap is required but absent."""
        return cls("codemode sandbox failed to start: bubblewrap binary path is unset")

    @classmethod
    def timed_out(cls, timeout_sec: float) -> SandboxError:
        """Create an error when sandboxed execution exceeds its wall clock limit."""
        return cls(f"codemode execution timed out after {timeout_sec:.0f}s")

    @classmethod
    def execution_failed(cls, detail: str) -> SandboxError:
        """Create an error when model-written code throws an uncaught error."""
        return cls(detail)


@dataclass
class SandboxConfig:
    """Runtime paths and isolation flags for running the JS sandbox."""

    node_bin: str
    bwrap_bin: str | None
    sandbox_script: Path
    use_bwrap: bool = True
    timeout_sec: float = DEFAULT_EXEC_TIMEOUT_SEC


@dataclass
class SandboxResult:
    """Outcome of one sandboxed Code Mode script execution."""

    value: object
    logs: list[str] = field(default_factory=list[str])


type RpcHandler = Callable[[str, dict[str, object]], object]


def _build_command(config: SandboxConfig) -> list[str]:
    script_str = str(config.sandbox_script.resolve())
    node_args = [
        config.node_bin,
        "--no-warnings=ExperimentalWarning",
        "--permission",
        f"--allow-fs-read={script_str}",
        "--disable-proto=throw",
        f"--max-old-space-size={NODE_MAX_HEAP_MB}",
        script_str,
    ]
    if not config.use_bwrap:
        return node_args

    if not config.bwrap_bin:
        raise SandboxError.missing_bwrap()

    # Mount only /nix/store (read-only) plus the script path if outside /nix/store (for tests).
    bwrap_args = [
        config.bwrap_bin,
        "--unshare-all",
        "--die-with-parent",
        "--new-session",
        "--ro-bind",
        "/nix/store",
        "/nix/store",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--tmpfs",
        SANDBOX_TMP_MOUNT,
        "--chdir",
        SANDBOX_TMP_MOUNT,
    ]
    if not script_str.startswith("/nix/store/"):
        bwrap_args.extend(["--ro-bind", script_str, script_str])
    bwrap_args.append("--")
    bwrap_args.extend(node_args)
    return bwrap_args


def _terminate_proc(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except OSError:
        proc.terminate()
    try:
        proc.wait(timeout=KILL_GRACE_SEC)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            proc.kill()
        proc.wait()


def _drain_stderr(proc: subprocess.Popen[str], chunks: list[str]) -> None:
    if proc.stderr is None:
        return
    with contextlib.suppress(OSError, ValueError):
        chunks.extend(proc.stderr)


def _as_dict(value: object) -> dict[str, object] | None:
    if not isinstance(value, dict):
        return None
    raw = cast("dict[object, object]", value)
    return {str(k): v for k, v in raw.items()}


def _dispatch_rpc(
    msg: dict[str, object],
    rpc_handler: RpcHandler,
    send_message: Callable[[dict[str, object]], None],
) -> None:
    req_id = msg.get("id")
    method = str(msg.get("method", ""))
    params = _as_dict(msg.get("params")) or {}
    try:
        rpc_result = rpc_handler(method, params)
        send_message({"type": "rpc_result", "id": req_id, "ok": True, "result": rpc_result})
    except Exception as exc:  # noqa: BLE001
        send_message({"type": "rpc_result", "id": req_id, "ok": False, "error": str(exc)})


def _parse_done(msg: dict[str, object]) -> SandboxResult:
    raw_logs = msg.get("logs")
    logs: list[str] = []
    if isinstance(raw_logs, list):
        logs = [str(entry) for entry in cast("list[object]", raw_logs)]
    return SandboxResult(value=msg.get("value"), logs=logs)


def _read_sandbox_loop(
    proc: subprocess.Popen[str],
    rpc_handler: RpcHandler,
    send_message: Callable[[dict[str, object]], None],
) -> tuple[SandboxResult | None, str | None]:
    if proc.stdout is None:
        return None, None
    for raw_line in proc.stdout:
        stripped = raw_line.strip()
        if not stripped:
            continue
        try:
            parsed: object = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        msg = _as_dict(parsed)
        if msg is None:
            continue
        msg_type = msg.get("type")
        if msg_type == "rpc":
            _dispatch_rpc(msg, rpc_handler, send_message)
        elif msg_type == "done":
            return _parse_done(msg), None
        elif msg_type == "error":
            return None, str(msg.get("error", "sandbox execution error"))
    return None, None


def _cleanup_sandbox_proc(
    proc: subprocess.Popen[str],
    timer: threading.Timer,
    stderr_thread: threading.Thread,
) -> None:
    timer.cancel()
    if proc.stdin is not None and not proc.stdin.closed:
        with contextlib.suppress(OSError):
            proc.stdin.close()
    deadline = time.monotonic() + KILL_GRACE_SEC
    while proc.poll() is None and time.monotonic() < deadline:
        time.sleep(0.01)
    _terminate_proc(proc)
    for stream in (proc.stdout, proc.stderr):
        if stream is not None:
            with contextlib.suppress(OSError):
                stream.close()
    stderr_thread.join(timeout=KILL_GRACE_SEC)


def run_sandbox(
    *,
    code: str,
    mode: str,
    server_aliases: dict[str, str],
    rpc_handler: RpcHandler,
    config: SandboxConfig,
) -> SandboxResult:
    """Run model-written JS/TS inside an isolated Node 24 sandbox with stdin/stdout RPC."""
    cmd = _build_command(config)
    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env={"NO_COLOR": "1"},
            start_new_session=True,
        )
    except OSError as exc:
        raise SandboxError.startup_failed(str(exc)) from None

    stderr_chunks: list[str] = []
    stderr_thread = threading.Thread(target=_drain_stderr, args=(proc, stderr_chunks), daemon=True)
    stderr_thread.start()

    timed_out = threading.Event()
    timer = threading.Timer(
        config.timeout_sec,
        lambda: (timed_out.set(), _terminate_proc(proc)),
    )
    timer.daemon = True
    timer.start()

    write_lock = threading.Lock()

    def send_message(msg: dict[str, object]) -> None:
        line = json.dumps(msg, separators=(",", ":")) + "\n"
        with write_lock:
            if proc.stdin is not None and not proc.stdin.closed:
                proc.stdin.write(line)
                proc.stdin.flush()

    final_result: SandboxResult | None = None
    final_error: str | None = None

    try:
        send_message(
            {
                "type": "run",
                "code": code,
                "mode": mode,
                "serverAliases": server_aliases,
            }
        )
        final_result, final_error = _read_sandbox_loop(proc, rpc_handler, send_message)
    finally:
        _cleanup_sandbox_proc(proc, timer, stderr_thread)

    if timed_out.is_set():
        raise SandboxError.timed_out(config.timeout_sec)
    if final_error is not None:
        raise SandboxError.execution_failed(final_error)
    if final_result is None:
        stderr_text = "".join(stderr_chunks).strip()
        detail = stderr_text or f"sandbox exited with code {proc.returncode}"
        raise SandboxError.startup_failed(detail)
    return final_result


def truncate_text(text: str, limit: int = MAX_TEXT_CHARS) -> str:
    """Truncate text outputs past the token budget, matching Cloudflare Code Mode."""
    if len(text) <= limit:
        return text
    return text[:limit] + TRUNCATION_MARKER
