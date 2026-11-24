# Copyright (c) 2026 Bad3r

"""Upstream MCP clients (stdio and Streamable HTTP) and lazy supervisor."""

from __future__ import annotations

import codecs
import contextlib
import http.client
import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast, override

from ._util import (
    PACKAGE_INFO,
    PROTOCOL_VERSION,
    RPC_METHOD_NOT_FOUND,
    as_dict,
    as_dict_list,
    terminate_process_group,
)
from .config import ConfigError, Manifest, ServerSpec, format_secret_header

if TYPE_CHECKING:
    from collections.abc import Generator, Iterator
    from http.client import HTTPResponse
    from typing import IO

ALLOWED_SCHEMES = ("http", "https")
NO_BODY_STATUSES = (202, 204)
HTTP_NOT_FOUND = 404
CLOSE_TIMEOUT_SEC = 5.0
STDIO_TERM_GRACE_SEC = 2.0
MAX_HTTP_RESPONSE_BYTES = 16 * 1024 * 1024
HTTP_READ_CHUNK_BYTES = 16 * 1024
MAX_TOOL_PAGES = 100
MIN_EFFECTIVE_TIMEOUT_SEC = 0.05
STDIO_CANCEL_POLL_SEC = 0.05


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
        return cls(f"upstream '{server}' timed out on {method} after {timeout:.1f}s")

    @classmethod
    def cancelled(cls, server: str, method: str) -> UpstreamError:
        """Create an error when an upstream request is cancelled."""
        return cls(f"upstream '{server}' cancelled during {method}")


def _extract_rpc_result(server: str, response: dict[str, object]) -> dict[str, object]:
    err_obj = response.get("error")
    if err_obj is not None:
        err_dict = as_dict(err_obj)
        msg = str(err_dict.get("message", err_dict)) if err_dict is not None else str(err_obj)
        raise UpstreamError.rpc_error(server, msg)
    result = as_dict(response.get("result"))
    return result if result is not None else {}


def _is_jsonrpc_response(msg: dict[str, object]) -> bool:
    return "method" not in msg and ("result" in msg or "error" in msg)


def _remaining_timeout(
    server: str,
    method: str,
    base_timeout: float,
    deadline: float | None,
) -> float:
    if deadline is None:
        return base_timeout
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise UpstreamError.timed_out(server, method, 0.0)
    return min(base_timeout, max(MIN_EFFECTIVE_TIMEOUT_SEC, remaining))


def _set_response_timeout(resp: HTTPResponse, remaining: float) -> None:
    fp = getattr(resp, "fp", None)
    raw = getattr(fp, "raw", None)
    sock = getattr(raw, "_sock", None)
    if isinstance(sock, socket.socket):
        with contextlib.suppress(OSError):
            sock.settimeout(max(MIN_EFFECTIVE_TIMEOUT_SEC, remaining))


def _close_response_hard(resp: HTTPResponse) -> None:
    fp = getattr(resp, "fp", None)
    raw = getattr(fp, "raw", None)
    sock = getattr(raw, "_sock", None)
    if isinstance(sock, socket.socket):
        # Shutdown unblocks the owning reader thread without racing BufferedReader.close().
        with contextlib.suppress(OSError):
            sock.shutdown(socket.SHUT_RDWR)
        return
    with contextlib.suppress(OSError, ValueError, RuntimeError):
        resp.close()


class _SameOriginRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Allow redirects only when scheme and host:port match the configured origin."""

    def __init__(self, expected_origin: tuple[str, str]) -> None:
        super().__init__()
        self._expected_origin = expected_origin

    @override
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: http.client.HTTPMessage,
        newurl: str,
    ) -> urllib.request.Request | None:
        resolved = urllib.parse.urljoin(req.full_url, newurl)
        parsed = urllib.parse.urlsplit(resolved)
        target_origin = (parsed.scheme.lower(), parsed.netloc.lower())
        if target_origin != self._expected_origin:
            raise urllib.error.HTTPError(
                resolved,
                code,
                f"refused cross-origin redirect to {parsed.scheme}://{parsed.netloc}",
                headers,
                fp,
            )
        return super().redirect_request(req, fp, code, msg, headers, resolved)


@dataclass(frozen=True)
class _CallContext:
    deadline: float | None = None
    cancel_event: threading.Event | None = None


def _read_http_chunk(resp: HTTPResponse) -> bytes:
    read1 = getattr(resp, "read1", None)
    if callable(read1):
        return cast("bytes", read1(HTTP_READ_CHUNK_BYTES))
    return resp.read(HTTP_READ_CHUNK_BYTES)


def _check_http_read_bounds(resp: HTTPResponse, server: str, ctx: _CallContext) -> None:
    if ctx.cancel_event is not None and ctx.cancel_event.is_set():
        raise UpstreamError.cancelled(server, "http_read")
    if ctx.deadline is not None:
        remaining = ctx.deadline - time.monotonic()
        if remaining <= 0:
            raise UpstreamError.timed_out(server, "http_read", 0.0)
        _set_response_timeout(resp, remaining)


def _iter_bounded_chunks(
    resp: HTTPResponse,
    server: str,
    *,
    is_gzip: bool,
    ctx: _CallContext,
) -> Iterator[bytes]:
    decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS) if is_gzip else None
    raw_total = 0
    decoded_total = 0
    while True:
        _check_http_read_bounds(resp, server, ctx)
        chunk = _read_http_chunk(resp)
        if not chunk:
            if ctx.cancel_event is not None and ctx.cancel_event.is_set():
                raise UpstreamError.cancelled(server, "http_read")
            break
        raw_total += len(chunk)
        if raw_total > MAX_HTTP_RESPONSE_BYTES:
            msg = f"HTTP response exceeded {MAX_HTTP_RESPONSE_BYTES} bytes"
            raise UpstreamError.rpc_error(server, msg)
        data = (
            decompressor.decompress(chunk, MAX_HTTP_RESPONSE_BYTES - decoded_total + 1)
            if decompressor is not None
            else chunk
        )
        decoded_total += len(data)
        if decoded_total > MAX_HTTP_RESPONSE_BYTES or (
            decompressor is not None and decompressor.unconsumed_tail
        ):
            msg = f"decompressed response exceeded {MAX_HTTP_RESPONSE_BYTES} bytes"
            raise UpstreamError.rpc_error(server, msg)
        if data:
            yield data
    if decompressor is not None:
        tail = decompressor.flush()
        if decoded_total + len(tail) > MAX_HTTP_RESPONSE_BYTES:
            msg = f"decompressed response exceeded {MAX_HTTP_RESPONSE_BYTES} bytes"
            raise UpstreamError.rpc_error(server, msg)
        if tail:
            yield tail


def _read_bounded_bytes(
    resp: HTTPResponse,
    server: str,
    *,
    is_gzip: bool,
    ctx: _CallContext,
) -> bytes:
    return b"".join(_iter_bounded_chunks(resp, server, is_gzip=is_gzip, ctx=ctx))


class _SseEventScanner:
    """Incremental SSE event parser returning as soon as target_id matches."""

    def __init__(self, target_id: int | None) -> None:
        self._target_id = target_id
        self._data_lines: list[str] = []
        self._line_buf = ""

    def _flush_event(self) -> dict[str, object] | None:
        if not self._data_lines:
            return None
        raw_event = "\n".join(self._data_lines)
        self._data_lines.clear()
        if not raw_event.strip():
            return None
        try:
            parsed_obj: object = json.loads(raw_event)
        except json.JSONDecodeError:
            return None
        parsed = as_dict(parsed_obj)
        if parsed is None or not _is_jsonrpc_response(parsed):
            return None
        if self._target_id is None or parsed.get("id") == self._target_id:
            return parsed
        return None

    def _feed_line(self, line: str) -> dict[str, object] | None:
        clean = line.removesuffix("\r")
        if clean == "":
            return self._flush_event()
        if clean.startswith("data:"):
            self._data_lines.append(clean[5:].removeprefix(" "))
        return None

    def feed(self, text: str) -> dict[str, object] | None:
        """Feed decoded UTF-8 text and return the first matching JSON-RPC response."""
        self._line_buf += text
        while "\n" in self._line_buf:
            line, self._line_buf = self._line_buf.split("\n", 1)
            matched = self._feed_line(line)
            if matched is not None:
                return matched
        return None

    def finish(self) -> dict[str, object] | None:
        """Flush any trailing buffered line or event at EOF."""
        if self._line_buf:
            matched = self._feed_line(self._line_buf)
            self._line_buf = ""
            if matched is not None:
                return matched
        return self._flush_event()


def _read_sse_response(
    resp: HTTPResponse,
    server: str,
    target_id: int | None,
    *,
    is_gzip: bool,
    ctx: _CallContext,
) -> dict[str, object]:
    scanner = _SseEventScanner(target_id)
    decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
    for chunk in _iter_bounded_chunks(resp, server, is_gzip=is_gzip, ctx=ctx):
        text = decoder.decode(chunk, final=False)
        if text:
            matched = scanner.feed(text)
            if matched is not None:
                return matched
    trailing = decoder.decode(b"", final=True)
    if trailing:
        matched = scanner.feed(trailing)
        if matched is not None:
            return matched
    final = scanner.finish()
    if final is None:
        msg = "empty SSE response"
        raise UpstreamError.rpc_error(server, msg)
    return final


class _BaseUpstreamClient:
    """Shared MCP pagination and tool invocation built atop transport-specific RPCs."""

    spec: ServerSpec
    _init_lock: threading.Lock

    @contextlib.contextmanager
    def _acquire_init_lock(
        self,
        deadline: float | None,
        cancel_event: threading.Event | None,
    ) -> Generator[None]:
        while True:
            if cancel_event is not None and cancel_event.is_set():
                raise UpstreamError.cancelled(self.spec.name, "initialize")
            if deadline is not None:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise UpstreamError.timed_out(self.spec.name, "initialize", 0.0)
                wait = min(remaining, STDIO_CANCEL_POLL_SEC)
            else:
                wait = STDIO_CANCEL_POLL_SEC
            if self._init_lock.acquire(timeout=wait):
                break
        try:
            yield
        finally:
            self._init_lock.release()

    def ensure_initialized(
        self,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> None:
        raise NotImplementedError

    def _rpc_call(
        self,
        method: str,
        params: dict[str, object],
        timeout: float,
        *,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object]:
        raise NotImplementedError

    def cancel_matching(self) -> None:
        """Abort any in-flight calls whose cancel_event has been triggered."""
        raise NotImplementedError

    def list_tools(
        self,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> list[dict[str, object]]:
        """Fetch all tools from the upstream server with cursor cycle protection."""
        self.ensure_initialized(deadline=deadline, cancel_event=cancel_event)
        tools: list[dict[str, object]] = []
        cursor: str | None = None
        seen_cursors: set[str] = set()
        for _ in range(MAX_TOOL_PAGES):
            params: dict[str, object] = {}
            if cursor is not None:
                params["cursor"] = cursor
            result = self._rpc_call(
                "tools/list",
                params,
                self.spec.startup_timeout_sec,
                deadline=deadline,
                cancel_event=cancel_event,
            )
            tools.extend(as_dict_list(result.get("tools")))
            next_cursor = result.get("nextCursor")
            if not isinstance(next_cursor, str) or not next_cursor:
                return tools
            if next_cursor in seen_cursors:
                msg = f"repeated pagination cursor '{next_cursor}' in tools/list"
                raise UpstreamError.rpc_error(self.spec.name, msg)
            seen_cursors.add(next_cursor)
            cursor = next_cursor
        msg = f"tools/list exceeded {MAX_TOOL_PAGES} pages"
        raise UpstreamError.rpc_error(self.spec.name, msg)

    def call_tool(
        self,
        tool_name: str,
        arguments: dict[str, object],
        *,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object]:
        """Invoke a single tool on the upstream server."""
        self.ensure_initialized(deadline=deadline, cancel_event=cancel_event)
        return self._rpc_call(
            "tools/call",
            {"name": tool_name, "arguments": arguments},
            self.spec.tool_timeout_sec,
            deadline=deadline,
            cancel_event=cancel_event,
        )

    def close(self) -> None:
        raise NotImplementedError


class HttpUpstreamClient(_BaseUpstreamClient):
    """Streamable HTTP MCP client supporting SSE, gzip, sessions, and secret headers."""

    def __init__(self, spec: ServerSpec) -> None:
        """Initialize an HTTP MCP client for a single server spec."""
        if spec.url is None:
            msg = "missing URL"
            raise UpstreamError.rpc_error(spec.name, msg)
        parsed = urllib.parse.urlsplit(spec.url)
        scheme = parsed.scheme.lower()
        if scheme not in ALLOWED_SCHEMES:
            raise UpstreamError.invalid_scheme(spec.name, scheme)
        self.spec = spec
        self.url = spec.url
        self._opener = urllib.request.build_opener(
            _SameOriginRedirectHandler((scheme, parsed.netloc.lower()))
        )
        self._lock = threading.Lock()
        self._init_lock = threading.Lock()
        self._next_id = 1
        self._next_inflight_id = 1
        self._inflight: dict[int, tuple[HTTPResponse, threading.Event | None]] = {}
        self._session_id: str | None = None
        self._protocol_version: str | None = None
        self._initialized = False
        self._closed = False

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
        # self.url is restricted to http/https and redirects are same-origin guarded.
        req = urllib.request.Request(  # noqa: S310
            self.url,
            data=data,
            headers=headers,
            method=method,
        )
        return cast("HTTPResponse", self._opener.open(req, timeout=timeout))

    def _headers(self, *, include_session: bool = True) -> dict[str, str]:
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
        if include_session:
            with self._lock:
                if self._session_id:
                    headers["Mcp-Session-Id"] = self._session_id
                if self._protocol_version:
                    headers["MCP-Protocol-Version"] = self._protocol_version
        return headers

    def _decode_response_body(
        self,
        resp: HTTPResponse,
        target_id: int | None,
        ctx: _CallContext,
    ) -> dict[str, object]:
        is_gzip = "gzip" in (resp.headers.get("Content-Encoding") or "").lower()
        content_type = (resp.headers.get("Content-Type") or "").lower()
        if "text/event-stream" in content_type:
            return _read_sse_response(
                resp,
                self.spec.name,
                target_id,
                is_gzip=is_gzip,
                ctx=ctx,
            )

        body = _read_bounded_bytes(resp, self.spec.name, is_gzip=is_gzip, ctx=ctx)
        text = body.decode("utf-8").strip()
        if not text:
            msg = "empty JSON response"
            raise UpstreamError.rpc_error(self.spec.name, msg)
        parsed_obj: object = json.loads(text)
        if isinstance(parsed_obj, list):
            for item in as_dict_list(cast("object", parsed_obj)):
                if _is_jsonrpc_response(item) and item.get("id") == target_id:
                    return item
            msg = "missing matching id in batch"
            raise UpstreamError.rpc_error(self.spec.name, msg)
        parsed_dict = as_dict(parsed_obj)
        if parsed_dict is None:
            msg = "non-object JSON-RPC reply"
            raise UpstreamError.rpc_error(self.spec.name, msg)
        return parsed_dict

    def _should_retry_session(
        self,
        code: int,
        *,
        sent_session_id: str | None,
        allow_session_retry: bool,
        method: object,
    ) -> bool:
        return (
            code == HTTP_NOT_FOUND
            and sent_session_id is not None
            and allow_session_retry
            and method not in ("initialize", "notifications/initialized")
        )

    def _register_inflight(
        self,
        resp: HTTPResponse,
        cancel_event: threading.Event | None,
    ) -> int:
        with self._lock:
            if self._closed:
                raise UpstreamError.closed(self.spec.name)
            token = self._next_inflight_id
            self._next_inflight_id += 1
            self._inflight[token] = (resp, cancel_event)
            return token

    def _unregister_inflight(self, token: int) -> None:
        with self._lock:
            self._inflight.pop(token, None)

    @override
    def cancel_matching(self) -> None:
        with self._lock:
            to_abort = [
                resp for resp, ev in self._inflight.values() if ev is not None and ev.is_set()
            ]
        for resp in to_abort:
            _close_response_hard(resp)

    def _renew_expired_session(self, sent_session_id: str, ctx: _CallContext) -> None:
        with self._acquire_init_lock(ctx.deadline, ctx.cancel_event):
            with self._lock:
                if self._closed:
                    raise UpstreamError.closed(self.spec.name)
                if self._session_id == sent_session_id:
                    self._session_id = None
                    self._protocol_version = None
                    self._initialized = False
                elif self._initialized:
                    return
            self._initialize_locked(ctx)

    def _post(
        self,
        payload: dict[str, object],
        timeout: float,
        *,
        expect_reply: bool,
        allow_session_retry: bool = True,
        ctx: _CallContext | None = None,
    ) -> dict[str, object]:
        call_ctx = ctx or _CallContext()
        method = str(payload.get("method", "request"))
        if call_ctx.cancel_event is not None and call_ctx.cancel_event.is_set():
            raise UpstreamError.cancelled(self.spec.name, method)
        effective_timeout = _remaining_timeout(self.spec.name, method, timeout, call_ctx.deadline)
        raw_id = payload.get("id") if expect_reply else None
        target_id = raw_id if isinstance(raw_id, int) else None
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers = self._headers(include_session=method != "initialize")
        sent_session_id = headers.get("Mcp-Session-Id")
        try:
            with self._open(
                method="POST",
                headers=headers,
                data=raw,
                timeout=effective_timeout,
            ) as resp:
                token = self._register_inflight(resp, call_ctx.cancel_event)
                try:
                    new_session = resp.headers.get("Mcp-Session-Id")
                    if new_session:
                        with self._lock:
                            self._session_id = new_session
                    if not expect_reply:
                        return {}
                    if resp.status in NO_BODY_STATUSES:
                        msg = f"unexpected HTTP {resp.status} for request expecting reply"
                        raise UpstreamError.rpc_error(self.spec.name, msg)
                    return self._decode_response_body(resp, target_id, call_ctx)
                finally:
                    self._unregister_inflight(token)
        except urllib.error.HTTPError as exc:
            exc.close()
            if sent_session_id is not None and self._should_retry_session(
                exc.code,
                sent_session_id=sent_session_id,
                allow_session_retry=allow_session_retry,
                method=payload.get("method"),
            ):
                self._renew_expired_session(sent_session_id, call_ctx)
                return self._post(
                    payload,
                    timeout,
                    expect_reply=expect_reply,
                    allow_session_retry=False,
                    ctx=call_ctx,
                )
            raise UpstreamError.rpc_error(self.spec.name, f"HTTP {exc.code} {exc.reason}") from None
        except (
            urllib.error.URLError,
            http.client.HTTPException,
            OSError,
            UnicodeDecodeError,
            json.JSONDecodeError,
            zlib.error,
        ) as exc:
            if call_ctx.cancel_event is not None and call_ctx.cancel_event.is_set():
                raise UpstreamError.cancelled(self.spec.name, method) from None
            raise UpstreamError.rpc_error(self.spec.name, str(exc)) from None

    @override
    def _rpc_call(
        self,
        method: str,
        params: dict[str, object],
        timeout: float,
        *,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object]:
        reply = self._post(
            {
                "jsonrpc": "2.0",
                "id": self._allocate_id(),
                "method": method,
                "params": params,
            },
            timeout,
            expect_reply=True,
            ctx=_CallContext(deadline=deadline, cancel_event=cancel_event),
        )
        return _extract_rpc_result(self.spec.name, reply)

    def _initialize_locked(self, ctx: _CallContext) -> None:
        with self._lock:
            self._session_id = None
            self._protocol_version = None
        init_req: dict[str, object] = {
            "jsonrpc": "2.0",
            "id": self._allocate_id(),
            "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": PACKAGE_INFO,
            },
        }
        try:
            reply = self._post(
                init_req,
                self.spec.startup_timeout_sec,
                expect_reply=True,
                allow_session_retry=False,
                ctx=ctx,
            )
            result = _extract_rpc_result(self.spec.name, reply)
            negotiated = result.get("protocolVersion")
            if isinstance(negotiated, str) and negotiated:
                with self._lock:
                    self._protocol_version = negotiated
            self._post(
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                self.spec.startup_timeout_sec,
                expect_reply=False,
                allow_session_retry=False,
                ctx=ctx,
            )
        except Exception:
            with self._lock:
                self._session_id = None
                self._protocol_version = None
                self._initialized = False
            raise
        with self._lock:
            if self._closed:
                self._session_id = None
                self._protocol_version = None
                raise UpstreamError.closed(self.spec.name)
            self._initialized = True

    @override
    def ensure_initialized(
        self,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> None:
        """Run MCP initialize handshake once per session."""
        with self._lock:
            if self._closed:
                raise UpstreamError.closed(self.spec.name)
            if self._initialized:
                return
        with self._acquire_init_lock(deadline, cancel_event):
            with self._lock:
                if self._closed:
                    raise UpstreamError.closed(self.spec.name)
                if self._initialized:
                    return
            self._initialize_locked(_CallContext(deadline=deadline, cancel_event=cancel_event))

    @override
    def close(self) -> None:
        """Abort active responses and send best-effort HTTP session termination."""
        with self._lock:
            self._closed = True
            session_id = self._session_id
            protocol_version = self._protocol_version
            self._session_id = None
            self._protocol_version = None
            self._initialized = False
            inflight = [resp for resp, _ in self._inflight.values()]
            self._inflight.clear()
        for resp in inflight:
            _close_response_hard(resp)
        if not session_id:
            return
        with contextlib.suppress(
            urllib.error.URLError, http.client.HTTPException, OSError, RuntimeError
        ):
            headers = self._headers(include_session=False)
            headers["Mcp-Session-Id"] = session_id
            if protocol_version:
                headers["MCP-Protocol-Version"] = protocol_version
            self._open(
                method="DELETE",
                headers=headers,
                timeout=min(self.spec.startup_timeout_sec, CLOSE_TIMEOUT_SEC),
            ).close()


class _PendingCall:
    def __init__(self, cancel_event: threading.Event | None = None) -> None:
        """Initialize an event-backed RPC response slot."""
        self.event = threading.Event()
        self.cancel_event = cancel_event
        self.cancelled = False
        self.response: dict[str, object] | None = None
        self.error: Exception | None = None


class StdioUpstreamClient(_BaseUpstreamClient):
    """Managed stdio MCP client with background response demultiplexing."""

    def __init__(self, spec: ServerSpec) -> None:
        """Initialize a stdio MCP client for a single server spec."""
        if spec.command is None:
            msg = "missing command"
            raise UpstreamError.rpc_error(spec.name, msg)
        self.spec = spec
        self._command = spec.command
        self._lock = threading.Lock()
        self._init_lock = threading.Lock()
        self._write_lock = threading.Lock()
        self._proc: subprocess.Popen[str] | None = None
        self._next_id = 1
        self._pending: dict[int, _PendingCall] = {}
        self._initialized = False
        self._closed = False

    def _build_env(self) -> dict[str, str]:
        env = dict(os.environ)
        env.update(self.spec.env)
        return env

    @staticmethod
    def _close_proc_handles(proc: subprocess.Popen[str]) -> None:
        for stream in (proc.stdin, proc.stdout, proc.stderr):
            if stream is not None:
                with contextlib.suppress(OSError, ValueError, RuntimeError):
                    stream.close()

    def _start_process_locked(self) -> None:
        if self._closed:
            raise UpstreamError.closed(self.spec.name)
        if self._proc is not None and self._proc.poll() is None:
            return
        old_proc = self._proc
        self._proc = None
        self._initialized = False
        if old_proc is not None:
            with contextlib.suppress(OSError):
                old_proc.wait(timeout=0.1)
            self._close_proc_handles(old_proc)

        cmd = [self._command, *self.spec.args]
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
                env=self._build_env(),
                start_new_session=True,
            )
        except OSError as exc:
            raise UpstreamError.rpc_error(self.spec.name, f"failed to spawn: {exc}") from None

        pending: dict[int, _PendingCall] = {}
        self._proc = proc
        self._pending = pending
        threading.Thread(target=self._read_stdout, args=(proc, pending), daemon=True).start()
        threading.Thread(target=self._read_stderr, args=(proc,), daemon=True).start()

    def _read_stderr(self, proc: subprocess.Popen[str]) -> None:
        if proc.stderr is None:
            return
        with contextlib.suppress(OSError, ValueError):
            for line in proc.stderr:
                sys.stderr.write(f"[mcp-codemode:{self.spec.name}] {line}")
                sys.stderr.flush()

    def _reply_server_request(
        self,
        proc: subprocess.Popen[str],
        msg_id: object,
        method: str,
    ) -> None:
        if method == "ping":
            reply: dict[str, object] = {"jsonrpc": "2.0", "id": msg_id, "result": {}}
        else:
            reply = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {
                    "code": RPC_METHOD_NOT_FOUND,
                    "message": f"Unsupported server request: {method}",
                },
            }
        with contextlib.suppress(UpstreamError, OSError):
            self._send_raw_to(proc, reply)

    def _handle_stdout_message(
        self,
        proc: subprocess.Popen[str],
        pending: dict[int, _PendingCall],
        msg: dict[str, object],
    ) -> None:
        msg_id = msg.get("id")
        method = msg.get("method")
        if isinstance(method, str):
            if msg_id is not None:
                self._reply_server_request(proc, msg_id, method)
            return
        if not isinstance(msg_id, int) or isinstance(msg_id, bool) or not _is_jsonrpc_response(msg):
            return
        with self._lock:
            waiter = pending.pop(msg_id, None)
        if waiter is not None:
            waiter.response = msg
            waiter.event.set()

    def _read_stdout(
        self,
        proc: subprocess.Popen[str],
        pending: dict[int, _PendingCall],
    ) -> None:
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
                    msg = as_dict(parsed)
                    if msg is not None:
                        self._handle_stdout_message(proc, pending, msg)
        finally:
            with self._lock:
                for waiter in pending.values():
                    waiter.error = UpstreamError.closed(self.spec.name)
                    waiter.event.set()
                pending.clear()
                if self._proc is proc:
                    self._initialized = False

    def _send_raw_to(self, proc: subprocess.Popen[str], payload: dict[str, object]) -> None:
        line = json.dumps(payload, separators=(",", ":")) + "\n"
        try:
            with self._write_lock:
                if proc.stdin is None or proc.stdin.closed or proc.poll() is not None:
                    raise UpstreamError.closed(self.spec.name)
                proc.stdin.write(line)
                proc.stdin.flush()
        except (OSError, ValueError) as exc:
            raise UpstreamError.rpc_error(self.spec.name, f"write failed: {exc}") from None

    def _send_raw(self, payload: dict[str, object]) -> None:
        with self._lock:
            proc = self._proc
        if proc is None:
            raise UpstreamError.closed(self.spec.name)
        self._send_raw_to(proc, payload)

    def _send_cancelled_notification(self, proc: subprocess.Popen[str], msg_id: int) -> None:
        with contextlib.suppress(UpstreamError, OSError):
            self._send_raw_to(
                proc,
                {
                    "jsonrpc": "2.0",
                    "method": "notifications/cancelled",
                    "params": {"requestId": msg_id, "reason": "cancelled"},
                },
            )

    @override
    def cancel_matching(self) -> None:
        cancelled_ids: list[tuple[subprocess.Popen[str], int]] = []
        with self._lock:
            proc = self._proc
            for msg_id, waiter in list(self._pending.items()):
                if waiter.cancel_event is not None and waiter.cancel_event.is_set():
                    waiter.cancelled = True
                    self._pending.pop(msg_id, None)
                    waiter.event.set()
                    if proc is not None:
                        cancelled_ids.append((proc, msg_id))
        for proc, msg_id in cancelled_ids:
            self._send_cancelled_notification(proc, msg_id)

    def _wait_for_reply(
        self,
        waiter: _PendingCall,
        effective_timeout: float,
        cancel_event: threading.Event | None,
    ) -> tuple[bool, bool]:
        if cancel_event is None:
            return waiter.event.wait(effective_timeout), waiter.cancelled
        end = time.monotonic() + effective_timeout
        while True:
            if waiter.cancelled or cancel_event.is_set():
                return False, True
            remaining = end - time.monotonic()
            if remaining <= 0:
                return waiter.event.is_set(), waiter.cancelled
            if waiter.event.wait(timeout=min(remaining, STDIO_CANCEL_POLL_SEC)):
                return True, waiter.cancelled

    @override
    def _rpc_call(
        self,
        method: str,
        params: dict[str, object],
        timeout: float,
        *,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object]:
        if cancel_event is not None and cancel_event.is_set():
            raise UpstreamError.cancelled(self.spec.name, method)
        effective_timeout = _remaining_timeout(self.spec.name, method, timeout, deadline)
        waiter = _PendingCall(cancel_event=cancel_event)
        with self._lock:
            proc = self._proc
            pending = self._pending
            if self._closed or proc is None:
                raise UpstreamError.closed(self.spec.name)
            msg_id = self._next_id
            self._next_id += 1
            pending[msg_id] = waiter
        try:
            self._send_raw_to(
                proc,
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "method": method,
                    "params": params,
                },
            )
        except Exception:
            with self._lock:
                pending.pop(msg_id, None)
            raise

        ready, was_cancelled = self._wait_for_reply(waiter, effective_timeout, cancel_event)
        if was_cancelled:
            with self._lock:
                still_pending = pending.pop(msg_id, None) is not None
            if still_pending:
                self._send_cancelled_notification(proc, msg_id)
            raise UpstreamError.cancelled(self.spec.name, method)
        if not ready:
            with self._lock:
                pending.pop(msg_id, None)
            raise UpstreamError.timed_out(self.spec.name, method, effective_timeout)
        if waiter.error is not None:
            raise waiter.error
        if waiter.response is None:
            raise UpstreamError.closed(self.spec.name)
        return _extract_rpc_result(self.spec.name, waiter.response)

    def _stop_process(self, *, mark_closed: bool) -> None:
        with self._lock:
            if mark_closed:
                self._closed = True
            proc = self._proc
            self._proc = None
            self._initialized = False
            pending_waiters = list(self._pending.values())
            self._pending.clear()
        for waiter in pending_waiters:
            waiter.error = UpstreamError.closed(self.spec.name)
            waiter.event.set()
        if proc is None:
            return
        # Acquire _write_lock with a short timeout so a blocked write cannot deadlock teardown.
        acquired = self._write_lock.acquire(timeout=0.1)
        try:
            if acquired and proc.stdin is not None:
                with contextlib.suppress(OSError, ValueError, RuntimeError):
                    proc.stdin.close()
        finally:
            if acquired:
                self._write_lock.release()
        terminate_process_group(proc, STDIO_TERM_GRACE_SEC)
        self._close_proc_handles(proc)

    @override
    def ensure_initialized(
        self,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> None:
        """Spawn the subprocess and perform the MCP handshake once."""
        with self._lock:
            if self._closed:
                raise UpstreamError.closed(self.spec.name)
            if self._initialized and self._proc is not None and self._proc.poll() is None:
                return
        with self._acquire_init_lock(deadline, cancel_event):
            with self._lock:
                if self._closed:
                    raise UpstreamError.closed(self.spec.name)
                if self._initialized and self._proc is not None and self._proc.poll() is None:
                    return
                self._start_process_locked()

            try:
                self._rpc_call(
                    "initialize",
                    {
                        "protocolVersion": PROTOCOL_VERSION,
                        "capabilities": {},
                        "clientInfo": PACKAGE_INFO,
                    },
                    self.spec.startup_timeout_sec,
                    deadline=deadline,
                    cancel_event=cancel_event,
                )
                self._send_raw({"jsonrpc": "2.0", "method": "notifications/initialized"})
            except Exception:
                self._stop_process(mark_closed=False)
                raise
            with self._lock:
                if self._closed:
                    raise UpstreamError.closed(self.spec.name)
                self._initialized = True

    @override
    def close(self) -> None:
        """Permanently close the client and terminate its process group."""
        self._stop_process(mark_closed=True)


class UpstreamSupervisor:
    """Lazily manages upstream MCP clients and caches discovered tool schemas."""

    def __init__(self, manifest: Manifest) -> None:
        """Initialize the supervisor for a compiled manifest."""
        self.manifest = manifest
        self._lock = threading.Lock()
        self._clients: dict[str, _BaseUpstreamClient] = {}
        self._tools_cache: dict[str, list[dict[str, object]]] = {}

    def _get_client(self, name: str) -> _BaseUpstreamClient:
        with self._lock:
            existing = self._clients.get(name)
            if existing is not None:
                return existing
            spec = self.manifest.servers[name]
            client: _BaseUpstreamClient = (
                HttpUpstreamClient(spec) if spec.transport == "http" else StdioUpstreamClient(spec)
            )
            self._clients[name] = client
            return client

    def get_tools(
        self,
        name: str,
        *,
        refresh: bool = False,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> list[dict[str, object]]:
        """Return cached or freshly fetched tool definitions for one server."""
        with self._lock:
            if not refresh and name in self._tools_cache:
                return list(self._tools_cache[name])
        client = self._get_client(name)
        tools = client.list_tools(deadline=deadline, cancel_event=cancel_event)
        with self._lock:
            self._tools_cache[name] = list(tools)
        return tools

    def call_tool(
        self,
        name: str,
        tool_name: str,
        arguments: dict[str, object],
        *,
        deadline: float | None = None,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object]:
        """Invoke a tool on the named upstream server."""
        client = self._get_client(name)
        return client.call_tool(
            tool_name,
            arguments,
            deadline=deadline,
            cancel_event=cancel_event,
        )

    def cancel_active(self) -> None:
        """Signal every active upstream client to abort cancelled in-flight calls."""
        with self._lock:
            clients = list(self._clients.values())
        for client in clients:
            client.cancel_matching()

    def close_disabled(self, states: dict[str, bool]) -> None:
        """Close and evict cached state for any server currently disabled."""
        to_close: list[_BaseUpstreamClient] = []
        with self._lock:
            for name, enabled in states.items():
                if not enabled:
                    self._tools_cache.pop(name, None)
                    client = self._clients.pop(name, None)
                    if client is not None:
                        to_close.append(client)
        for client in to_close:
            with contextlib.suppress(Exception):
                client.close()

    def close_all(self) -> None:
        """Close every active upstream client."""
        with self._lock:
            clients = list(self._clients.values())
            self._clients.clear()
            self._tools_cache.clear()
        for client in clients:
            with contextlib.suppress(Exception):
                client.close()
