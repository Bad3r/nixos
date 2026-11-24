# Copyright (c) 2026 Bad3r

"""Upstream MCP clients (stdio and Streamable HTTP) and lazy supervisor."""

from __future__ import annotations

import contextlib
import gzip
import json
import os
import signal
import subprocess
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import zlib
from typing import TYPE_CHECKING, cast

from .config import ConfigError, Manifest, ServerSpec, format_secret_header

if TYPE_CHECKING:
    from http.client import HTTPResponse

PROTOCOL_VERSION = "2025-03-26"
CLIENT_INFO = {"name": "mcp-codemode", "version": "0.1.0"}
ALLOWED_SCHEMES = ("http", "https")
NO_BODY_STATUSES = (202, 204)
HTTP_NOT_FOUND = 404
CLOSE_TIMEOUT_SEC = 5.0
STDIO_TERM_GRACE_SEC = 2.0


class UpstreamError(RuntimeError):
    """Raised when an upstream MCP server cannot initialize or complete a call."""

    @classmethod
    def invalid_scheme(cls, server: str, scheme: str) -> UpstreamError:
        """Create an error for an unsupported URL scheme."""
        return cls(f"upstream '{server}' has unsupported URL scheme {scheme!r}")

    @classmethod
    def rpc_error(cls, server: str, detail: str) -> UpstreamError:
        """Create an error for a failed JSON-RPC or HTTP call."""
        return cls(f"upstream '{server}': {detail}")

    @classmethod
    def closed(cls, server: str) -> UpstreamError:
        """Create an error when a stdio subprocess exits unexpectedly."""
        return cls(f"upstream '{server}' closed unexpectedly")

    @classmethod
    def timed_out(cls, server: str, method: str, timeout: float) -> UpstreamError:
        """Create an error when an upstream request exceeds its timeout."""
        return cls(f"upstream '{server}' timed out on {method} after {timeout:.0f}s")


def _as_dict(value: object) -> dict[str, object] | None:
    if not isinstance(value, dict):
        return None
    raw = cast("dict[object, object]", value)
    return {str(k): v for k, v in raw.items()}


def _as_dict_list(value: object) -> list[dict[str, object]]:
    if not isinstance(value, list):
        return []
    out: list[dict[str, object]] = []
    for item in cast("list[object]", value):
        item_dict = _as_dict(item)
        if item_dict is not None:
            out.append(item_dict)
    return out


def _extract_rpc_result(server: str, response: dict[str, object]) -> dict[str, object]:
    err_obj = response.get("error")
    if err_obj is not None:
        err_dict = _as_dict(err_obj)
        msg = str(err_dict.get("message", err_dict)) if err_dict is not None else str(err_obj)
        raise UpstreamError.rpc_error(server, msg)
    result = _as_dict(response.get("result"))
    return result if result is not None else {}


class HttpUpstreamClient:
    """Streamable HTTP MCP client supporting SSE, gzip, sessions, and secret headers."""

    def __init__(self, spec: ServerSpec) -> None:
        """Initialize an HTTP MCP client for a single server spec."""
        if spec.url is None:
            msg = "missing URL"
            raise UpstreamError.rpc_error(spec.name, msg)
        scheme = urllib.parse.urlsplit(spec.url).scheme.lower()
        if scheme not in ALLOWED_SCHEMES:
            raise UpstreamError.invalid_scheme(spec.name, scheme)
        self.spec = spec
        self.url = spec.url
        self._lock = threading.Lock()
        self._next_id = 1
        self._session_id: str | None = None
        self._protocol_version: str | None = None
        self._initialized = False

    def _allocate_id(self) -> int:
        with self._lock:
            msg_id = self._next_id
            self._next_id += 1
            return msg_id

    def _open(
        self,
        *,
        method: str,
        headers: dict[str, str],
        data: bytes | None = None,
        timeout: float,
    ) -> HTTPResponse:
        # self.url is restricted to http/https in __init__.
        req = urllib.request.Request(  # noqa: S310
            self.url,
            data=data,
            headers=headers,
            method=method,
        )
        return urllib.request.urlopen(req, timeout=timeout)  # noqa: S310

    def _headers(self) -> dict[str, str]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.spec.secret_header is not None:
            try:
                headers[self.spec.secret_header.name] = format_secret_header(
                    self.spec.secret_header
                )
            except ConfigError as exc:
                raise UpstreamError.rpc_error(self.spec.name, str(exc)) from None
        with self._lock:
            if self._session_id:
                headers["Mcp-Session-Id"] = self._session_id
            if self._protocol_version:
                headers["MCP-Protocol-Version"] = self._protocol_version
        return headers

    def _parse_sse(self, body: bytes, target_id: int | None) -> dict[str, object] | None:
        data_lines: list[str] = []
        matched: dict[str, object] | None = None

        def flush() -> None:
            nonlocal matched
            if not data_lines:
                return
            raw_event = "\n".join(data_lines)
            data_lines.clear()
            if not raw_event.strip():
                return
            try:
                parsed_obj: object = json.loads(raw_event)
            except json.JSONDecodeError:
                return
            parsed = _as_dict(parsed_obj)
            if parsed is not None and (target_id is None or parsed.get("id") == target_id):
                matched = parsed

        for line in body.decode("utf-8", errors="replace").splitlines():
            if line == "":
                flush()
            elif line.startswith("data:"):
                data_lines.append(line[5:].removeprefix(" "))
        flush()
        return matched

    def _decode_response_body(
        self,
        resp: HTTPResponse,
        target_id: int | None,
    ) -> dict[str, object]:
        body = resp.read()
        if "gzip" in (resp.headers.get("Content-Encoding") or "").lower():
            body = gzip.decompress(body)
        content_type = (resp.headers.get("Content-Type") or "").lower()
        if "text/event-stream" in content_type:
            reply = self._parse_sse(body, target_id)
            if reply is None:
                msg = "empty SSE response"
                raise UpstreamError.rpc_error(self.spec.name, msg)
            return reply
        text = body.decode("utf-8").strip()
        if not text:
            msg = "empty JSON response"
            raise UpstreamError.rpc_error(self.spec.name, msg)
        parsed_obj: object = json.loads(text)
        if isinstance(parsed_obj, list):
            for item in _as_dict_list(cast("object", parsed_obj)):
                if item.get("id") == target_id:
                    return item
            msg = "missing matching id in batch"
            raise UpstreamError.rpc_error(self.spec.name, msg)
        parsed_dict = _as_dict(parsed_obj)
        if parsed_dict is None:
            msg = "non-object JSON-RPC reply"
            raise UpstreamError.rpc_error(self.spec.name, msg)
        return parsed_dict

    def _post(
        self,
        payload: dict[str, object],
        timeout: float,
        *,
        expect_reply: bool,
        allow_session_retry: bool = True,
    ) -> dict[str, object]:
        raw_id = payload.get("id") if expect_reply else None
        target_id = raw_id if isinstance(raw_id, int) else None
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers = self._headers()
        had_session = "Mcp-Session-Id" in headers
        try:
            with self._open(
                method="POST",
                headers=headers,
                data=raw,
                timeout=timeout,
            ) as resp:
                new_session = resp.headers.get("Mcp-Session-Id")
                if new_session:
                    with self._lock:
                        self._session_id = new_session
                if not expect_reply or resp.status in NO_BODY_STATUSES:
                    return {}
                return self._decode_response_body(resp, target_id)
        except urllib.error.HTTPError as exc:
            exc.close()
            if (
                exc.code == HTTP_NOT_FOUND
                and had_session
                and allow_session_retry
                and payload.get("method") != "initialize"
            ):
                with self._lock:
                    self._session_id = None
                    self._protocol_version = None
                    self._initialized = False
                self.ensure_initialized()
                return self._post(
                    payload,
                    timeout,
                    expect_reply=expect_reply,
                    allow_session_retry=False,
                )
            raise UpstreamError.rpc_error(self.spec.name, f"HTTP {exc.code} {exc.reason}") from None
        except (urllib.error.URLError, OSError, json.JSONDecodeError, zlib.error) as exc:
            raise UpstreamError.rpc_error(self.spec.name, str(exc)) from None

    def ensure_initialized(self) -> None:
        """Run MCP initialize handshake once per session."""
        with self._lock:
            if self._initialized:
                return
        init_req: dict[str, object] = {
            "jsonrpc": "2.0",
            "id": self._allocate_id(),
            "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": CLIENT_INFO,
            },
        }
        reply = self._post(init_req, self.spec.startup_timeout_sec, expect_reply=True)
        result = _extract_rpc_result(self.spec.name, reply)
        negotiated = result.get("protocolVersion")
        if isinstance(negotiated, str) and negotiated:
            with self._lock:
                self._protocol_version = negotiated
        self._post(
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            self.spec.startup_timeout_sec,
            expect_reply=False,
        )
        with self._lock:
            self._initialized = True

    def list_tools(self) -> list[dict[str, object]]:
        """Fetch all tools from the upstream server, following pagination cursors."""
        self.ensure_initialized()
        tools: list[dict[str, object]] = []
        cursor: str | None = None
        while True:
            params: dict[str, object] = {}
            if cursor is not None:
                params["cursor"] = cursor
            reply = self._post(
                {
                    "jsonrpc": "2.0",
                    "id": self._allocate_id(),
                    "method": "tools/list",
                    "params": params,
                },
                self.spec.startup_timeout_sec,
                expect_reply=True,
            )
            result = _extract_rpc_result(self.spec.name, reply)
            tools.extend(_as_dict_list(result.get("tools")))
            next_cursor = result.get("nextCursor")
            if not isinstance(next_cursor, str) or not next_cursor:
                break
            cursor = next_cursor
        return tools

    def call_tool(self, tool_name: str, arguments: dict[str, object]) -> dict[str, object]:
        """Invoke a single tool on the upstream HTTP server."""
        self.ensure_initialized()
        reply = self._post(
            {
                "jsonrpc": "2.0",
                "id": self._allocate_id(),
                "method": "tools/call",
                "params": {"name": tool_name, "arguments": arguments},
            },
            self.spec.tool_timeout_sec,
            expect_reply=True,
        )
        return _extract_rpc_result(self.spec.name, reply)

    def close(self) -> None:
        """Best-effort HTTP session termination."""
        with self._lock:
            session_id = self._session_id
            self._initialized = False
        if not session_id:
            return
        with contextlib.suppress(urllib.error.URLError, OSError, RuntimeError):
            self._open(
                method="DELETE",
                headers=self._headers(),
                timeout=min(self.spec.startup_timeout_sec, CLOSE_TIMEOUT_SEC),
            ).close()


class _PendingCall:
    def __init__(self) -> None:
        """Initialize an event-backed RPC response slot."""
        self.event = threading.Event()
        self.response: dict[str, object] | None = None
        self.error: Exception | None = None


class StdioUpstreamClient:
    """Managed stdio MCP client with background response demultiplexing."""

    def __init__(self, spec: ServerSpec) -> None:
        """Initialize a stdio MCP client for a single server spec."""
        if spec.command is None:
            msg = "missing command"
            raise UpstreamError.rpc_error(spec.name, msg)
        self.spec = spec
        self._lock = threading.Lock()
        self._write_lock = threading.Lock()
        self._proc: subprocess.Popen[str] | None = None
        self._next_id = 1
        self._pending: dict[int, _PendingCall] = {}
        self._initialized = False

    def _build_env(self) -> dict[str, str]:
        env = dict(os.environ)
        env.update(self.spec.env)
        return env

    def _start_process_locked(self) -> None:
        if self._proc is not None and self._proc.poll() is None:
            return
        self._initialized = False
        if self.spec.command is None:
            msg = "missing command"
            raise UpstreamError.rpc_error(self.spec.name, msg)
        cmd = [self.spec.command, *self.spec.args]
        try:
            # New process group ensures clean teardown of wrapper + child trees.
            proc = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
                env=self._build_env(),
                start_new_session=True,
            )
        except OSError as exc:
            raise UpstreamError.rpc_error(self.spec.name, f"failed to spawn: {exc}") from None

        self._proc = proc
        threading.Thread(target=self._read_stdout, args=(proc,), daemon=True).start()
        threading.Thread(target=self._read_stderr, args=(proc,), daemon=True).start()

    def _read_stderr(self, proc: subprocess.Popen[str]) -> None:
        if proc.stderr is None:
            return
        with contextlib.suppress(OSError, ValueError):
            for line in proc.stderr:
                sys.stderr.write(f"[mcp-codemode:{self.spec.name}] {line}")
                sys.stderr.flush()

    def _read_stdout(self, proc: subprocess.Popen[str]) -> None:
        if proc.stdout is None:
            return
        try:
            with contextlib.suppress(OSError, ValueError):
                for line in proc.stdout:
                    stripped = line.strip()
                    if not stripped:
                        continue
                    try:
                        parsed: object = json.loads(stripped)
                    except json.JSONDecodeError:
                        continue
                    msg = _as_dict(parsed)
                    if msg is None:
                        continue
                    msg_id = msg.get("id")
                    if not isinstance(msg_id, int):
                        continue
                    with self._lock:
                        waiter = self._pending.pop(msg_id, None)
                    if waiter is not None:
                        waiter.response = msg
                        waiter.event.set()
        finally:
            with self._lock:
                for waiter in self._pending.values():
                    waiter.error = UpstreamError.closed(self.spec.name)
                    waiter.event.set()
                self._pending.clear()
                if self._proc is proc:
                    self._initialized = False

    def _send_raw(self, payload: dict[str, object]) -> None:
        proc = self._proc
        if proc is None or proc.stdin is None or proc.poll() is not None:
            raise UpstreamError.closed(self.spec.name)
        line = json.dumps(payload, separators=(",", ":")) + "\n"
        try:
            with self._write_lock:
                proc.stdin.write(line)
                proc.stdin.flush()
        except OSError as exc:
            raise UpstreamError.rpc_error(self.spec.name, f"write failed: {exc}") from None

    def _request(
        self,
        method: str,
        params: dict[str, object],
        timeout: float,
    ) -> dict[str, object]:
        waiter = _PendingCall()
        with self._lock:
            msg_id = self._next_id
            self._next_id += 1
            self._pending[msg_id] = waiter
        try:
            self._send_raw(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "method": method,
                    "params": params,
                }
            )
        except Exception:
            with self._lock:
                self._pending.pop(msg_id, None)
            raise

        if not waiter.event.wait(timeout):
            with self._lock:
                self._pending.pop(msg_id, None)
            raise UpstreamError.timed_out(self.spec.name, method, timeout)
        if waiter.error is not None:
            raise waiter.error
        if waiter.response is None:
            raise UpstreamError.closed(self.spec.name)
        return _extract_rpc_result(self.spec.name, waiter.response)

    def ensure_initialized(self) -> None:
        """Spawn the subprocess and perform the MCP handshake once."""
        with self._lock:
            if self._initialized and self._proc is not None and self._proc.poll() is None:
                return
            self._start_process_locked()

        self._request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": CLIENT_INFO,
            },
            self.spec.startup_timeout_sec,
        )
        self._send_raw({"jsonrpc": "2.0", "method": "notifications/initialized"})
        with self._lock:
            self._initialized = True

    def list_tools(self) -> list[dict[str, object]]:
        """List all tools from the stdio server."""
        self.ensure_initialized()
        tools: list[dict[str, object]] = []
        cursor: str | None = None
        while True:
            params: dict[str, object] = {}
            if cursor is not None:
                params["cursor"] = cursor
            result = self._request("tools/list", params, self.spec.startup_timeout_sec)
            tools.extend(_as_dict_list(result.get("tools")))
            next_cursor = result.get("nextCursor")
            if not isinstance(next_cursor, str) or not next_cursor:
                break
            cursor = next_cursor
        return tools

    def call_tool(self, tool_name: str, arguments: dict[str, object]) -> dict[str, object]:
        """Call one tool on the stdio server."""
        self.ensure_initialized()
        return self._request(
            "tools/call",
            {"name": tool_name, "arguments": arguments},
            self.spec.tool_timeout_sec,
        )

    def close(self) -> None:
        """Terminate the upstream process group cleanly."""
        with self._lock:
            proc = self._proc
            self._proc = None
            self._initialized = False
        if proc is None:
            return
        if proc.stdin is not None:
            with contextlib.suppress(OSError):
                proc.stdin.close()
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except OSError:
                proc.terminate()
            try:
                proc.wait(timeout=STDIO_TERM_GRACE_SEC)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    proc.kill()
                proc.wait()
        for stream in (proc.stdout, proc.stderr):
            if stream is not None:
                with contextlib.suppress(OSError):
                    stream.close()


class UpstreamSupervisor:
    """Lazily manages upstream MCP clients and caches discovered tool schemas."""

    def __init__(self, manifest: Manifest) -> None:
        """Initialize the supervisor for a compiled manifest."""
        self.manifest = manifest
        self._lock = threading.Lock()
        self._clients: dict[str, HttpUpstreamClient | StdioUpstreamClient] = {}
        self._tools_cache: dict[str, list[dict[str, object]]] = {}

    def _get_client(self, name: str) -> HttpUpstreamClient | StdioUpstreamClient:
        with self._lock:
            existing = self._clients.get(name)
            if existing is not None:
                return existing
            spec = self.manifest.servers[name]
            client: HttpUpstreamClient | StdioUpstreamClient = (
                HttpUpstreamClient(spec) if spec.transport == "http" else StdioUpstreamClient(spec)
            )
            self._clients[name] = client
            return client

    def get_tools(self, name: str, *, refresh: bool = False) -> list[dict[str, object]]:
        """Return cached or freshly fetched tool definitions for one server."""
        with self._lock:
            if not refresh and name in self._tools_cache:
                return list(self._tools_cache[name])
        client = self._get_client(name)
        tools = client.list_tools()
        with self._lock:
            self._tools_cache[name] = list(tools)
        return tools

    def call_tool(
        self,
        name: str,
        tool_name: str,
        arguments: dict[str, object],
    ) -> dict[str, object]:
        """Invoke a tool on the named upstream server."""
        client = self._get_client(name)
        return client.call_tool(tool_name, arguments)

    def close_all(self) -> None:
        """Close every active upstream client."""
        with self._lock:
            clients = list(self._clients.values())
            self._clients.clear()
            self._tools_cache.clear()
        for client in clients:
            client.close()
