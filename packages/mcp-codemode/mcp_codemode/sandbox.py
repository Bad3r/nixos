# Copyright (c) 2026 Bad3r

"""Sandboxed JavaScript/TypeScript execution via Bubblewrap and Node 24 permissions."""

from __future__ import annotations

import contextlib
import json
import queue
import subprocess
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, cast

from ._util import as_dict, terminate_process_group

if TYPE_CHECKING:
    from pathlib import Path

DEFAULT_EXEC_TIMEOUT_SEC = 120.0
MAX_TEXT_CHARS = 24_000
TRUNCATION_MARKER = "\n--- TRUNCATED ---"
NODE_MAX_HEAP_MB = 256
KILL_GRACE_SEC = 1.0
SANDBOX_TMP_MOUNT = "/tmp"  # noqa: S108
SANDBOX_TMPFS_BYTES = 16 * 1024 * 1024
MAX_SANDBOX_IPC_LINE_BYTES = 4 * 1024 * 1024
MAX_CONCURRENT_RPCS = 8
WAIT_POLL_SEC = 0.05


class SandboxError(RuntimeError):
    """Raised when the JS sandbox fails to start, times out, is cancelled, or throws."""

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
    def cancelled(cls) -> SandboxError:
        """Create an error when the client cancels an in-flight execution."""
        return cls("codemode execution cancelled")

    @classmethod
    def execution_failed(cls, detail: str, logs: list[str] | None = None) -> SandboxError:
        """Create an error when model-written code throws an uncaught error."""
        if logs:
            return cls("Console output:\n" + "\n".join(logs) + f"\n\n{detail}")
        return cls(detail)


@dataclass
class SandboxConfig:
    """Runtime paths and isolation flags for running the JS sandbox."""

    node_bin: str
    bwrap_bin: str | None
    sandbox_script: Path
    use_bwrap: bool = True
    timeout_sec: float = DEFAULT_EXEC_TIMEOUT_SEC
    cancel_event: threading.Event | None = field(default=None, repr=False)
    on_abort: Callable[[], None] | None = field(default=None, repr=False)


@dataclass
class SandboxResult:
    """Outcome of one sandboxed Code Mode script execution."""

    value: object
    logs: list[str] = field(default_factory=list[str])


type RpcHandler = Callable[[str, dict[str, object], float, threading.Event], object]


def build_command(config: SandboxConfig) -> list[str]:
    """Build the Node 24 (+ optional Bubblewrap) command line for a sandbox run."""
    script_str = str(config.sandbox_script.resolve())
    node_args = [
        config.node_bin,
        "--no-warnings=ExperimentalWarning",
        "--permission",
        f"--allow-fs-read={script_str}",
        "--disallow-code-generation-from-strings",
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
        "--cap-drop",
        "ALL",
        "--die-with-parent",
        "--new-session",
        "--ro-bind",
        "/nix/store",
        "/nix/store",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--size",
        str(SANDBOX_TMPFS_BYTES),
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


def _drain_stderr(proc: subprocess.Popen[str], chunks: list[str]) -> None:
    if proc.stderr is None:
        return
    with contextlib.suppress(OSError, ValueError):
        chunks.extend(proc.stderr)


def _extract_logs(msg: dict[str, object]) -> list[str]:
    raw_logs = msg.get("logs")
    if not isinstance(raw_logs, list):
        return []
    return [str(entry) for entry in cast("list[object]", raw_logs)]


class _SandboxSession:
    """Coordinates non-blocking stdin/stdout IPC, concurrent RPC dispatch, and deadline teardown."""

    def __init__(
        self,
        proc: subprocess.Popen[str],
        rpc_handler: RpcHandler,
        deadline: float,
        on_abort: Callable[[], None] | None = None,
    ) -> None:
        self.proc = proc
        self.rpc_handler = rpc_handler
        self.deadline = deadline
        self._on_abort = on_abort
        self._state_lock = threading.Lock()
        self._done_event = threading.Event()
        self._abort_event = threading.Event()
        self._write_queue: queue.Queue[dict[str, object] | None] = queue.Queue()
        self._rpc_sem = threading.Semaphore(MAX_CONCURRENT_RPCS)
        self.result: SandboxResult | None = None
        self.error: tuple[str, list[str]] | None = None
        self.timed_out = False
        self.cancelled = False

    def enqueue_write(self, msg: dict[str, object]) -> None:
        """Queue one JSON message for the dedicated stdin writer thread."""
        self._write_queue.put(msg)

    def _writer_loop(self) -> None:
        stdin = self.proc.stdin
        if stdin is None:
            return
        while True:
            msg = self._write_queue.get()
            if msg is None:
                return
            line = json.dumps(msg, separators=(",", ":")) + "\n"
            try:
                stdin.write(line)
                stdin.flush()
            except BrokenPipeError, OSError, ValueError:
                return

    def _run_rpc_task(self, req_id: object, method: str, params: dict[str, object]) -> None:
        with self._rpc_sem:
            if self._done_event.is_set() or self._abort_event.is_set():
                return
            try:
                rpc_result = self.rpc_handler(method, params, self.deadline, self._abort_event)
                reply: dict[str, object] = {
                    "type": "rpc_result",
                    "id": req_id,
                    "ok": True,
                    "result": rpc_result,
                }
            except Exception as exc:  # noqa: BLE001
                reply = {"type": "rpc_result", "id": req_id, "ok": False, "error": str(exc)}
            if not self._done_event.is_set() and not self._abort_event.is_set():
                self.enqueue_write(reply)

    def _reader_loop(self) -> None:
        stdout = self.proc.stdout
        if stdout is None:
            self._finish_eof()
            return
        try:
            with contextlib.suppress(OSError, ValueError):
                while True:
                    raw_line = stdout.readline(MAX_SANDBOX_IPC_LINE_BYTES + 1)
                    if not raw_line:
                        break
                    if len(raw_line) > MAX_SANDBOX_IPC_LINE_BYTES and not raw_line.endswith("\n"):
                        self._record_error(
                            f"sandbox IPC message exceeded {MAX_SANDBOX_IPC_LINE_BYTES} bytes",
                            [],
                        )
                        return
                    stripped = raw_line.strip()
                    if not stripped:
                        continue
                    try:
                        parsed: object = json.loads(stripped)
                    except json.JSONDecodeError:
                        continue
                    msg = as_dict(parsed)
                    if msg is not None and self._handle_message(msg):
                        return
        finally:
            self._finish_eof()

    def _record_error(self, detail: str, logs: list[str]) -> None:
        with self._state_lock:
            if not self._done_event.is_set():
                self.error = (detail, logs)
                self._done_event.set()

    def _handle_message(self, msg: dict[str, object]) -> bool:
        msg_type = msg.get("type")
        if msg_type == "rpc":
            req_id = msg.get("id")
            method = str(msg.get("method", ""))
            params = as_dict(msg.get("params")) or {}
            if not self._done_event.is_set() and not self._abort_event.is_set():
                # Daemon workers prevent orphaned upstream RPCs from stalling interpreter exit.
                threading.Thread(
                    target=self._run_rpc_task,
                    args=(req_id, method, params),
                    daemon=True,
                ).start()
            return False
        if msg_type == "done":
            with self._state_lock:
                if not self._done_event.is_set():
                    self.result = SandboxResult(value=msg.get("value"), logs=_extract_logs(msg))
                    self._done_event.set()
            return True
        if msg_type == "error":
            self._record_error(
                str(msg.get("error", "sandbox execution error")),
                _extract_logs(msg),
            )
            return True
        return False

    def _finish_eof(self) -> None:
        with self._state_lock:
            self._done_event.set()

    def abort(self, *, timed_out: bool = False, cancelled: bool = False) -> None:
        """Mark the session aborted, signal upstream RPCs, and terminate the sandbox group."""
        should_kill = False
        with self._state_lock:
            if not self._done_event.is_set():
                self.timed_out = timed_out
                self.cancelled = cancelled
                self._abort_event.set()
                self._done_event.set()
                should_kill = True
        if should_kill:
            if self._on_abort is not None:
                with contextlib.suppress(Exception):
                    self._on_abort()
            terminate_process_group(self.proc, KILL_GRACE_SEC)

    def run_and_wait(
        self,
        init_msg: dict[str, object],
        cancel_event: threading.Event | None,
    ) -> None:
        """Run sandbox I/O threads and wait until done, cancelled, or expired."""
        writer = threading.Thread(target=self._writer_loop, daemon=True)
        reader = threading.Thread(target=self._reader_loop, daemon=True)
        writer.start()
        reader.start()
        self.enqueue_write(init_msg)
        try:
            while not self._done_event.is_set():
                if cancel_event is not None and cancel_event.is_set():
                    self.abort(cancelled=True)
                    break
                remaining = self.deadline - time.monotonic()
                if remaining <= 0:
                    self.abort(timed_out=True)
                    break
                self._done_event.wait(timeout=min(remaining, WAIT_POLL_SEC))
        finally:
            self._abort_event.set()
            self._write_queue.put(None)
            if self.proc.stdin is not None and not self.proc.stdin.closed:
                with contextlib.suppress(OSError):
                    self.proc.stdin.close()
            with contextlib.suppress(subprocess.TimeoutExpired):
                self.proc.wait(timeout=KILL_GRACE_SEC)
            terminate_process_group(self.proc, KILL_GRACE_SEC)
            for stream in (self.proc.stdout, self.proc.stderr):
                if stream is not None:
                    with contextlib.suppress(OSError):
                        stream.close()
            reader.join(timeout=KILL_GRACE_SEC)
            writer.join(timeout=KILL_GRACE_SEC)


def run_sandbox(
    *,
    code: str,
    mode: str,
    server_aliases: dict[str, str],
    rpc_handler: RpcHandler,
    config: SandboxConfig,
) -> SandboxResult:
    """Run model-written JS/TS inside an isolated Node 24 sandbox with stdin/stdout RPC."""
    if config.cancel_event is not None and config.cancel_event.is_set():
        raise SandboxError.cancelled()
    cmd = build_command(config)
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

    deadline = time.monotonic() + config.timeout_sec
    session = _SandboxSession(proc, rpc_handler, deadline, on_abort=config.on_abort)
    try:
        session.run_and_wait(
            {
                "type": "run",
                "code": code,
                "mode": mode,
                "serverAliases": server_aliases,
            },
            config.cancel_event,
        )
    finally:
        stderr_thread.join(timeout=KILL_GRACE_SEC)

    if session.cancelled:
        raise SandboxError.cancelled()
    if session.timed_out:
        raise SandboxError.timed_out(config.timeout_sec)
    if session.error is not None:
        detail, err_logs = session.error
        raise SandboxError.execution_failed(detail, err_logs)
    if session.result is None:
        stderr_text = "".join(stderr_chunks).strip()
        detail = stderr_text or f"sandbox exited with code {proc.returncode}"
        raise SandboxError.startup_failed(detail)
    return session.result


def truncate_text(text: str, limit: int = MAX_TEXT_CHARS) -> str:
    """Truncate text outputs past the token budget, matching Cloudflare Code Mode."""
    if len(text) <= limit:
        return text
    return text[:limit] + TRUNCATION_MARKER
