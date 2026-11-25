# Copyright (c) 2026 Bad3r

"""Tests for stdio and Streamable HTTP upstream MCP clients."""

from __future__ import annotations

import gzip
import http.server
import io
import json
import os
import signal
import sys
import tempfile
import threading
import time
import unittest
from contextlib import contextmanager, suppress
from pathlib import Path
from typing import TYPE_CHECKING, cast
from unittest import mock

from mcp_codemode._util import terminate_process_group
from mcp_codemode.config import SecretHeader, ServerSpec, load_manifest
from mcp_codemode.upstream import (
    MAX_BEST_EFFORT_SENDS,
    HttpUpstreamClient,
    StdioUpstreamClient,
    UpstreamError,
    UpstreamSupervisor,
    _BestEffortSends,  # pyright: ignore[reportPrivateUsage]
)

if TYPE_CHECKING:
    import subprocess
    from collections.abc import Callable, Generator

MOCK_STDIO_SCRIPT = """
import json, os, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        reply = {"protocolVersion": "2025-03-26", "capabilities": {}}
    elif method == "tools/list":
        cursor = msg.get("params", {}).get("cursor")
        if not cursor:
            reply = {
                "tools": [
                    {"name": "echo", "description": "Echo", "inputSchema": {"type": "object"}},
                ],
                "nextCursor": "p2",
            }
        else:
            reply = {
                "tools": [{"name": "add", "description": "Add", "inputSchema": {"type": "object"}}],
            }
    elif method == "tools/call":
        name = msg["params"]["name"]
        args = msg["params"]["arguments"]
        if name == "echo":
            # Send a server-initiated ping with colliding id before answering the tool call.
            print(json.dumps({"jsonrpc": "2.0", "id": mid, "method": "ping"}), flush=True)
            payload = {"echoed": args.get("msg"), "env": os.environ.get("MOCK_ENV", "")}
            reply = {"content": [{"type": "text", "text": json.dumps(payload)}]}
        else:
            total = str(args.get("a", 0) + args.get("b", 0))
            reply = {"content": [{"type": "text", "text": total}]}
    else:
        continue
    print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": reply}), flush=True)
"""


LIFECYCLE_STDIO_SCRIPT = """
import json, sys
spawn_log = sys.argv[1]
fail_first = len(sys.argv) > 2 and sys.argv[2] == "fail-first"
with open(spawn_log, "a+", encoding="utf-8") as log:
    log.seek(0)
    spawn = len(log.read().splitlines())
    log.write("spawn\\n")
hung, cancelled = [], []
def send(mid, **body):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, **body}) + "\\n")
    sys.stdout.flush()
for line in sys.stdin:
    msg = json.loads(line)
    method = msg.get("method")
    mid = msg.get("id")
    if method == "initialize":
        if fail_first and spawn == 0:
            send(mid, error={"code": -32000, "message": "first init fails"})
        else:
            send(mid, result={"protocolVersion": "2025-03-26"})
    elif method == "notifications/cancelled":
        cancelled.append(msg["params"]["requestId"])
    elif method == "tools/list":
        send(mid, result={"tools": [{"name": "hang", "description": "Hang"}]})
    elif method == "tools/call":
        if msg["params"]["name"] == "hang":
            hung.append(mid)
        else:
            text = json.dumps({"hung": hung, "cancelled": cancelled})
            send(mid, result={"content": [{"type": "text", "text": text}]})
"""

STALLING_STDIO_SCRIPT = """
import json, os, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
resume, received = sys.argv[1], sys.argv[2]
for line in sys.stdin:
    msg = json.loads(line)
    method, params = msg.get("method"), msg.get("params") or {}
    with open(received, "a", encoding="utf-8") as log:
        entry = [method, msg.get("id"), params.get("name"), params.get("requestId")]
        log.write(json.dumps(entry) + "\\n")
    if method == "initialize" and "no-init-reply" not in sys.argv:
        reply = {"jsonrpc": "2.0", "id": msg["id"], "result": {"protocolVersion": "2025-03-26"}}
        sys.stdout.write(json.dumps(reply) + "\\n")
        sys.stdout.flush()
    elif method == "notifications/initialized":
        while not os.path.exists(resume):
            time.sleep(0.02)
    elif method == "tools/call":
        reply = {"jsonrpc": "2.0", "id": msg["id"], "result": {"content": []}}
        sys.stdout.write(json.dumps(reply) + "\\n")
        sys.stdout.flush()
"""

WAIT_SEC = 5.0


class _LifecycleState:
    def __init__(self) -> None:
        self.cond = threading.Condition()
        self.init_count = 0
        self.list_count = 0
        self.deleted: list[str | None] = []
        self.cancelled: list[tuple[object, str | None]] = []
        self.hung_ids: list[object] = []
        self.received: list[tuple[str, object]] = []
        self.upload_entered = threading.Event()
        self.upload_gate: threading.Event | None = None
        self.init_entered = threading.Event()
        self.init_gate: threading.Event | None = None
        self.list_entered = threading.Event()
        self.list_gate: threading.Event | None = None
        self.release = threading.Event()
        self.initialized_status = 202
        self.delete_status = 204
        self.delete_started: list[str | None] = []
        self.delete_gate: threading.Event | None = None
        self.issue_session = True
        self.expired_sessions: set[str] = set()

    def append[T](self, items: list[T], item: T) -> None:
        with self.cond:
            items.append(item)
            self.cond.notify_all()

    def wait_for(self, predicate: Callable[[], bool], timeout: float = WAIT_SEC) -> bool:
        with self.cond:
            return self.cond.wait_for(predicate, timeout=timeout)


class _LifecycleHandler(http.server.BaseHTTPRequestHandler):
    state: _LifecycleState

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        del format, args

    def _reply(
        self,
        msg_id: object,
        result: dict[str, object],
        headers: dict[str, str] | None = None,
    ) -> None:
        payload = json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": result}).encode()
        # A client that timed out has already closed the connection.
        with suppress(BrokenPipeError, ConnectionResetError):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    def _empty(self, status: int) -> None:
        self.send_response(status)
        self.end_headers()

    def _initialize(self, msg_id: object, params: dict[str, object]) -> None:
        del params
        st = self.state
        with st.cond:
            st.init_count += 1
            session = f"sess-{st.init_count}"
            st.cond.notify_all()
        st.init_entered.set()
        if st.init_gate is not None:
            st.init_gate.wait(timeout=WAIT_SEC)
        headers = {"Mcp-Session-Id": session} if st.issue_session else {}
        self._reply(msg_id, {"protocolVersion": "2025-06-18"}, headers)

    def _initialized(self, msg_id: object, params: dict[str, object]) -> None:
        del msg_id, params
        self._empty(self.state.initialized_status)

    def _cancelled(self, msg_id: object, params: dict[str, object]) -> None:
        del msg_id
        entry = (params.get("requestId"), self.headers.get("Mcp-Session-Id"))
        self.state.append(self.state.received, ("cancelled", entry[0]))
        self.state.append(self.state.cancelled, entry)
        self._empty(202)

    def _tools_list(self, msg_id: object, params: dict[str, object]) -> None:
        del params
        st = self.state
        with st.cond:
            st.list_count += 1
        st.list_entered.set()
        if st.list_gate is not None:
            st.list_gate.wait(timeout=WAIT_SEC)
        self._reply(msg_id, {"tools": [{"name": "a", "description": "A"}]})

    def _tools_call(self, msg_id: object, params: dict[str, object]) -> None:
        st = self.state
        name = params.get("name")
        if name == "slow_upload":
            # Models a server still reading the request body.
            st.upload_entered.set()
            if st.upload_gate is not None:
                st.upload_gate.wait(timeout=WAIT_SEC)
        st.append(st.received, ("tools/call", msg_id))
        if name in ("session", "held_session"):
            # Reply with the request's session and echo it in the header, as some servers do.
            session = self.headers.get("Mcp-Session-Id")
            if name == "held_session":
                self.state.append(self.state.hung_ids, msg_id)
                self.state.release.wait(timeout=WAIT_SEC)
            content = [{"type": "text", "text": str(session)}]
            self._reply(msg_id, {"content": content}, {"Mcp-Session-Id": str(session)})
            return
        # Never replies: "hang" withholds headers, the others send SSE headers only.
        if name in ("stream_hang", "slow_upload"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            self.wfile.flush()
        self.state.append(self.state.hung_ids, msg_id)
        self.state.release.wait(timeout=WAIT_SEC)

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = cast("dict[str, object]", json.loads(self.rfile.read(length)))
        if self.headers.get("Mcp-Session-Id") in self.state.expired_sessions:
            self._empty(404)
            return
        handlers = {
            "initialize": self._initialize,
            "notifications/initialized": self._initialized,
            "notifications/cancelled": self._cancelled,
            "tools/list": self._tools_list,
            "tools/call": self._tools_call,
        }
        handler = handlers.get(str(body.get("method")))
        if handler is not None:
            handler(body.get("id"), cast("dict[str, object]", body.get("params") or {}))

    def do_DELETE(self) -> None:
        st = self.state
        session = self.headers.get("Mcp-Session-Id")
        st.append(st.delete_started, session)
        if st.delete_gate is not None:
            st.delete_gate.wait(timeout=WAIT_SEC)
        st.append(st.deleted, session)
        self._empty(st.delete_status)


def _make_lifecycle_handler(st: _LifecycleState) -> type[http.server.BaseHTTPRequestHandler]:
    class BoundHandler(_LifecycleHandler):
        state = st

    return BoundHandler


@contextmanager
def _running_server(st: _LifecycleState) -> Generator[str]:
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _make_lifecycle_handler(st))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{srv.server_address[1]}/mcp"
    finally:
        st.release.set()
        for gate in (st.init_gate, st.list_gate, st.delete_gate, st.upload_gate):
            if gate is not None:
                gate.set()
        srv.shutdown()
        srv.server_close()


def _close_drained(client: HttpUpstreamClient) -> bool:
    client.close()
    return client.drain(time.monotonic() + WAIT_SEC)


def _http_spec(url: str) -> ServerSpec:
    return ServerSpec(name="lc-http", alias="lc_http", transport="http", url=url)


def _run_capturing(target: Callable[[], object], errors: list[Exception]) -> threading.Thread:
    def _run() -> None:
        try:
            target()
        except Exception as exc:  # noqa: BLE001
            errors.append(exc)

    thread = threading.Thread(target=_run)
    thread.start()
    return thread


def _spawn_count(spawn_log: Path) -> int:
    return len(spawn_log.read_text(encoding="utf-8").splitlines()) if spawn_log.exists() else 0


class _HttpEdgeState:
    def __init__(self) -> None:
        self.sessions = ["sess-1", "sess-2"]
        self.expired_once = False
        self.tool_calls_seen = 0
        self.fail_next_404 = False
        self.corrupt_gzip_next = False
        self.sse_done_next = False
        self.sse_keep_open_next = False
        self.return_202_on_call = False
        self.init_notify_404 = False
        self.redirect_cross_origin = False
        self.repeat_cursor = False


class _EdgeHttpHandler(http.server.BaseHTTPRequestHandler):
    state: _HttpEdgeState

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        del format, args

    def _send_json(self, payload: bytes, *, headers: dict[str, str] | None = None) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = cast("dict[str, object]", json.loads(self.rfile.read(length).decode("utf-8")))
        method = body.get("method")
        msg_id = body.get("id")
        if self.state.redirect_cross_origin:
            self.send_response(307)
            self.send_header("Location", "https://attacker.invalid/mcp")
            self.end_headers()
            return
        if method == "initialize":
            sid = self.state.sessions.pop(0) if self.state.sessions else "sess-extra"
            payload = json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"protocolVersion": "2025-03-26"},
                }
            ).encode("utf-8")
            self._send_json(payload, headers={"Mcp-Session-Id": sid})
        elif method == "notifications/initialized":
            status = 404 if self.state.init_notify_404 else 202
            self.send_response(status)
            self.end_headers()
        elif method == "tools/list":
            page: dict[str, object] = {"tools": [{"name": "a", "description": "A"}]}
            if self.state.repeat_cursor:
                page["nextCursor"] = "loop"
            payload = json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": page}).encode("utf-8")
            self._send_json(payload)
        elif method == "tools/call":
            self._handle_tools_call(msg_id)

    def _send_sse_keep_open(self, msg_id: object) -> None:
        ev = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {"content": [{"type": "text", "text": "streamed-early"}]},
            }
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        self.wfile.write(f"data: {ev}\n\n".encode())
        self.wfile.flush()
        time.sleep(2.0)

    def _handle_tools_call(self, msg_id: object) -> None:
        self.state.tool_calls_seen += 1
        if self.state.return_202_on_call:
            self.send_response(202)
            self.end_headers()
            return
        if self.state.fail_next_404 or (
            not self.state.expired_once and self.headers.get("Mcp-Session-Id") == "sess-1"
        ):
            self.state.expired_once = True
            self.send_response(404)
            self.end_headers()
            return
        if self.state.corrupt_gzip_next:
            self._send_json(b"not-valid-gzip", headers={"Content-Encoding": "gzip"})
            return
        if self.state.sse_keep_open_next:
            self._send_sse_keep_open(msg_id)
            return
        if self.state.sse_done_next:
            ev = json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"content": [{"type": "text", "text": "after-done"}]},
                }
            )
            payload = f"data: {ev}\n\ndata: [DONE]\n\n".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        payload = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "content": [{"type": "text", "text": str(self.headers.get("Mcp-Session-Id"))}]
                },
            }
        ).encode("utf-8")
        self._send_json(payload)

    def do_DELETE(self) -> None:
        self.send_response(204)
        self.end_headers()


def _make_edge_handler(edge_state: _HttpEdgeState) -> type[http.server.BaseHTTPRequestHandler]:
    class BoundHandler(_EdgeHttpHandler):
        state = edge_state

    return BoundHandler


def _make_concurrency_handler(
    split_utf8_text: str,
    state: dict[str, object],
    lock: threading.Lock,
) -> type[http.server.BaseHTTPRequestHandler]:
    class ConcurrencyHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:  # noqa: A002
            _ = (format, args)

        def do_DELETE(self) -> None:
            headers_list = cast("list[tuple[str | None, str | None]]", state["delete_headers"])
            with lock:
                headers_list.append(
                    (
                        self.headers.get("Mcp-Session-Id"),
                        self.headers.get("MCP-Protocol-Version"),
                    )
                )
            self.send_response(204)
            self.end_headers()

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", "0"))
            req = cast("dict[str, object]", json.loads(self.rfile.read(length)))
            method = req.get("method")
            msg_id = req.get("id")
            if method == "initialize":
                time.sleep(0.05)
                with lock:
                    state["init_count"] = cast("int", state["init_count"]) + 1
                payload = json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "result": {"protocolVersion": "2025-06-18", "capabilities": {}},
                    }
                ).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Mcp-Session-Id", "sess-race")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            if method == "notifications/initialized":
                self.send_response(202)
                self.end_headers()
                return
            raw_event = (
                "data: "
                + json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "result": {"content": [{"type": "text", "text": split_utf8_text}]},
                    },
                    ensure_ascii=False,
                )
                + "\n\n"
            ).encode("utf-8")
            em_dash_idx = raw_event.index(b"\xe2\x80\x94")
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(raw_event)))
            self.end_headers()
            self.wfile.write(raw_event[: em_dash_idx + 1])
            self.wfile.flush()
            time.sleep(0.02)
            self.wfile.write(raw_event[em_dash_idx + 1 :])
            self.wfile.flush()

    return ConcurrencyHandler


class UpstreamTest(unittest.TestCase):
    """Covers HTTP SSE/gzip/session/redirect/secret headers and stdio pagination/teardown."""

    def test_http_upstream_sse_gzip_secret_and_close(self) -> None:
        """Handle SSE, gzip, pagination, secret headers, non-leak errors, and DELETE."""
        header_name = "X-Goog-Api-Key"
        header_value = "dummy-value"
        seen: list[dict[str, object]] = []
        deleted: list[tuple[str | None, str | None]] = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                del format, args

            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", "0"))
                body = cast(
                    "dict[str, object]", json.loads(self.rfile.read(length).decode("utf-8"))
                )
                seen.append(
                    {
                        "method": body.get("method"),
                        "header": self.headers.get(header_name),
                        "session": self.headers.get("Mcp-Session-Id"),
                        "version": self.headers.get("MCP-Protocol-Version"),
                    }
                )
                if self.headers.get(header_name) != header_value:
                    self.send_response(403)
                    self.end_headers()
                    return

                method = body.get("method")
                msg_id = body.get("id")
                if method == "initialize":
                    payload = json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "result": {"protocolVersion": "2025-06-18"},
                        }
                    ).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Mcp-Session-Id", "sess-99")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                elif method == "notifications/initialized":
                    self.send_response(202)
                    self.end_headers()
                elif method == "tools/list":
                    raw_params = body.get("params")
                    params_dict = (
                        cast("dict[str, object]", raw_params)
                        if isinstance(raw_params, dict)
                        else {}
                    )
                    cursor = params_dict.get("cursor")
                    page: dict[str, object] = (
                        {"tools": [{"name": "search", "description": "Search"}], "nextCursor": "n2"}
                        if not cursor
                        else {"tools": [{"name": "get", "description": "Get"}]}
                    )
                    payload = gzip.compress(
                        json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": page}).encode("utf-8")
                    )
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Encoding", "gzip")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                elif method == "tools/call":
                    ev1 = json.dumps({"jsonrpc": "2.0", "method": "notifications/progress"})
                    ev2 = json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "result": {"content": [{"type": "text", "text": "ok"}]},
                        }
                    )
                    payload = f"event: message\ndata: {ev1}\n\ndata: {ev2}\n\n".encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)

            def do_DELETE(self) -> None:
                deleted.append((self.headers.get("Mcp-Session-Id"), self.headers.get(header_name)))
                self.send_response(204)
                self.end_headers()

        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        port = srv.server_address[1]
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                data_dir = Path(tmp)
                secret_file = data_dir / "gdk" / "key"
                secret_file.parent.mkdir(parents=True, exist_ok=True)
                secret_file.write_text(header_value + "\n", encoding="utf-8")

                spec = ServerSpec(
                    name="gdk",
                    alias="gdk",
                    transport="http",
                    url=f"http://127.0.0.1:{port}/mcp",
                    secret_header=SecretHeader(name=header_name, relative_path="gdk/key"),
                )
                with mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(data_dir)}, clear=False):
                    client = HttpUpstreamClient(spec)
                    tools = client.list_tools()
                    self.assertEqual([t["name"] for t in tools], ["search", "get"])
                    res = client.call_tool("search", {"q": "nix"})
                    content = cast("list[dict[str, object]]", res["content"])
                    self.assertEqual(content[0]["text"], "ok")
                    self.assertTrue(_close_drained(client))

                after_init = [entry for entry in seen if entry["method"] != "initialize"]
                self.assertTrue(after_init)
                self.assertTrue(all(entry["session"] == "sess-99" for entry in after_init))
                self.assertTrue(all(entry["version"] == "2025-06-18" for entry in after_init))
                self.assertEqual(deleted, [("sess-99", header_value)])

                secret_file.write_text("wrong-value", encoding="utf-8")
                with mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(data_dir)}, clear=False):
                    bad_client = HttpUpstreamClient(spec)
                    with self.assertRaises(UpstreamError) as ctx:
                        bad_client.list_tools()
                    self.assertIn("403", str(ctx.exception))
                    self.assertNotIn("wrong-value", str(ctx.exception))
        finally:
            srv.shutdown()
            srv.server_close()

    def test_http_upstream_secret_header_prefix(self) -> None:
        """Prepend configured prefix when formatting secret HTTP headers."""
        received_auth: list[str | None] = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                del format, args

            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", "0"))
                body = cast(
                    "dict[str, object]", json.loads(self.rfile.read(length).decode("utf-8"))
                )
                received_auth.append(self.headers.get("Authorization"))
                if self.headers.get("Authorization") != "Bearer dummy-value":
                    self.send_response(403)
                    self.end_headers()
                    return
                method = body.get("method")
                msg_id = body.get("id")
                if method == "initialize":
                    payload = json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "result": {"protocolVersion": "2025-03-26"},
                        }
                    ).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                elif method == "notifications/initialized":
                    self.send_response(202)
                    self.end_headers()
                elif method == "tools/list":
                    payload = json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "result": {"tools": [{"name": "docs", "description": "Docs"}]},
                        }
                    ).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)

        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        port = srv.server_address[1]
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                data_dir = Path(tmp)
                secret_file = data_dir / "cloudflare" / "api-key"
                secret_file.parent.mkdir(parents=True, exist_ok=True)
                secret_file.write_text("dummy-value\n", encoding="utf-8")

                spec = ServerSpec(
                    name="cloudflare-api",
                    alias="cloudflare_api",
                    transport="http",
                    url=f"http://127.0.0.1:{port}/mcp",
                    secret_header=SecretHeader(
                        name="Authorization",
                        relative_path="cloudflare/api-key",
                        prefix="Bearer ",
                    ),
                )
                with mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(data_dir)}, clear=False):
                    client = HttpUpstreamClient(spec)
                    tools = client.list_tools()
                    self.assertEqual([t["name"] for t in tools], ["docs"])
                    self.assertTrue(_close_drained(client))
                self.assertTrue(received_auth)
                self.assertTrue(all(h == "Bearer dummy-value" for h in received_auth))
        finally:
            srv.shutdown()
            srv.server_close()

    def test_stdio_upstream_server_ping_and_supervisor(self) -> None:
        """Paginate stdio tools, handle server-initiated ping without id collision, and close."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / "mock_stdio.py"
            script.write_text(MOCK_STDIO_SCRIPT, encoding="utf-8")
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "client": "test",
                        "servers": {
                            "mock-stdio": {
                                "transport": "stdio",
                                "command": sys.executable,
                                "args": ["-u", str(script)],
                                "env": {"MOCK_ENV": "from-manifest"},
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            manifest = load_manifest(manifest_path)
            client = StdioUpstreamClient(manifest.servers["mock-stdio"])
            tools = client.list_tools()
            self.assertEqual([t["name"] for t in tools], ["echo", "add"])
            res = client.call_tool("echo", {"msg": "hi"})
            content = cast("list[dict[str, object]]", res["content"])
            self.assertEqual(
                json.loads(str(content[0]["text"])),
                {"echoed": "hi", "env": "from-manifest"},
            )
            client.close()

            supervisor = UpstreamSupervisor(manifest)
            try:
                cached = supervisor.get_tools("mock-stdio")
                self.assertEqual(len(cached), 2)
                added = supervisor.call_tool("mock-stdio", "add", {"a": 2, "b": 3})
                added_content = cast("list[dict[str, object]]", added["content"])
                self.assertEqual(added_content[0]["text"], "5")
                supervisor.close_disabled({"mock-stdio": False})
            finally:
                supervisor.close_all()

    def test_http_missing_secret_raises_upstream_error(self) -> None:
        """Surface missing secret files as UpstreamError rather than ConfigError."""
        with tempfile.TemporaryDirectory() as tmp:
            spec = ServerSpec(
                name="cloudflare-api",
                alias="cloudflare_api",
                transport="http",
                url="http://127.0.0.1:9/mcp",
                secret_header=SecretHeader(
                    name="Authorization",
                    relative_path="cloudflare/missing",
                    prefix="Bearer ",
                ),
            )
            with mock.patch.dict(os.environ, {"XDG_DATA_HOME": tmp}, clear=False):
                client = HttpUpstreamClient(spec)
                with self.assertRaises(UpstreamError):
                    client.list_tools()

    def test_http_session_reinit_and_incremental_sse(self) -> None:
        """Renew expired 404 sessions once, stream SSE without EOF, and cap 404 retries."""
        state = _HttpEdgeState()
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _make_edge_handler(state))
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            spec = ServerSpec(
                name="mock-http",
                alias="mock_http",
                transport="http",
                url=f"http://127.0.0.1:{port}/mcp",
            )
            client = HttpUpstreamClient(spec)
            res = client.call_tool("ping", {})
            content = cast("list[dict[str, object]]", res["content"])
            self.assertEqual(content[0]["text"], "sess-2")

            state.sse_done_next = True
            sse_res = client.call_tool("ping", {})
            state.sse_done_next = False
            sse_content = cast("list[dict[str, object]]", sse_res["content"])
            self.assertEqual(sse_content[0]["text"], "after-done")

            state.sse_keep_open_next = True
            t0 = time.monotonic()
            early_res = client.call_tool("ping", {})
            elapsed = time.monotonic() - t0
            state.sse_keep_open_next = False
            self.assertLess(elapsed, 1.0)
            early_content = cast("list[dict[str, object]]", early_res["content"])
            self.assertEqual(early_content[0]["text"], "streamed-early")

            before_calls = state.tool_calls_seen
            state.fail_next_404 = True
            with self.assertRaises(UpstreamError) as ctx:
                client.call_tool("ping", {})
            self.assertIn("404", str(ctx.exception))
            max_retry_calls = 2
            self.assertEqual(state.tool_calls_seen - before_calls, max_retry_calls)
            state.fail_next_404 = False
            self.assertTrue(_close_drained(client))

            # 404 on notifications/initialized must raise UpstreamError, never RecursionError.
            state.init_notify_404 = True
            fresh_client = HttpUpstreamClient(spec)
            with self.assertRaises(UpstreamError) as init_ctx:
                fresh_client.ensure_initialized()
            self.assertIn("404", str(init_ctx.exception))
            state.init_notify_404 = False
            self.assertTrue(_close_drained(fresh_client))
        finally:
            srv.shutdown()
            srv.server_close()

    def test_http_rejects_bad_202_gzip_redirect_and_cursor_loop(self) -> None:
        """Reject HTTP 202 replies, corrupt gzip, cross-origin redirects, and cursor loops."""
        state = _HttpEdgeState()
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _make_edge_handler(state))
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            spec = ServerSpec(
                name="mock-http",
                alias="mock_http",
                transport="http",
                url=f"http://127.0.0.1:{port}/mcp",
            )
            client = HttpUpstreamClient(spec)
            client.ensure_initialized()

            state.return_202_on_call = True
            with self.assertRaises(UpstreamError):
                client.call_tool("ping", {})
            state.return_202_on_call = False

            state.corrupt_gzip_next = True
            with self.assertRaises(UpstreamError):
                client.call_tool("ping", {})
            state.corrupt_gzip_next = False

            state.repeat_cursor = True
            with self.assertRaises(UpstreamError) as cursor_ctx:
                client.list_tools()
            self.assertIn("repeated pagination cursor", str(cursor_ctx.exception))
            state.repeat_cursor = False

            state.redirect_cross_origin = True
            with self.assertRaises(UpstreamError) as redir_ctx:
                client.call_tool("ping", {})
            self.assertIn("cross-origin", str(redir_ctx.exception))
            state.redirect_cross_origin = False
            self.assertTrue(_close_drained(client))
        finally:
            srv.shutdown()
            srv.server_close()

    def test_concurrent_init_split_utf8_sse_and_delete_protocol_header(self) -> None:
        """Serialize cold HTTP/stdio init, preserve split UTF-8 in SSE, and send protocol header."""
        lock = threading.Lock()
        split_utf8_text = "alpha — omega"
        state: dict[str, object] = {"init_count": 0, "delete_headers": []}
        handler_cls = _make_concurrency_handler(split_utf8_text, state, lock)
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler_cls)
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            spec = ServerSpec(
                name="race-http",
                alias="race_http",
                transport="http",
                url=f"http://127.0.0.1:{port}/mcp",
            )
            client = HttpUpstreamClient(spec)
            results: list[dict[str, object]] = []
            errors: list[Exception] = []

            def _worker() -> None:
                try:
                    results.append(client.call_tool("ping", {}))
                except Exception as exc:  # noqa: BLE001
                    errors.append(exc)

            threads = [threading.Thread(target=_worker) for _ in range(4)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(timeout=5.0)
            self.assertEqual(errors, [])
            self.assertEqual(state["init_count"], 1)
            expected_results = 4
            self.assertEqual(len(results), expected_results)
            for item in results:
                content = cast("list[dict[str, object]]", item["content"])
                self.assertEqual(content[0]["text"], split_utf8_text)
            self.assertTrue(_close_drained(client))
            self.assertEqual(state["delete_headers"], [("sess-race", "2025-06-18")])
        finally:
            srv.shutdown()
            srv.server_close()

    def test_stdio_concurrent_init_and_upstream_cancellation(self) -> None:
        """Reject duplicate stdio initialize and forward notifications/cancelled upstream."""
        script_body = """
import json, sys, time
initialized = False
cancelled = []
for line in sys.stdin:
    msg = json.loads(line)
    method = msg.get("method")
    msg_id = msg.get("id")
    if method == "initialize":
        time.sleep(0.05)
        if initialized:
            out = {"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32000, "message": "dup"}}
        else:
            initialized = True
            out = {"jsonrpc": "2.0", "id": msg_id, "result": {"protocolVersion": "2025-03-26"}}
        sys.stdout.write(json.dumps(out) + "\\n")
        sys.stdout.flush()
    elif method == "notifications/cancelled":
        cancelled.append(msg.get("params", {}).get("requestId"))
    elif method == "tools/call":
        name = msg["params"]["name"]
        if name == "sleep":
            time.sleep(3.0)
        elif name == "cancelled_ids":
            out = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {"content": [{"type": "text", "text": json.dumps(cancelled)}]},
            }
            sys.stdout.write(json.dumps(out) + "\\n")
            sys.stdout.flush()
        else:
            out = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {"content": [{"type": "text", "text": "ok"}]},
            }
            sys.stdout.write(json.dumps(out) + "\\n")
            sys.stdout.flush()
"""
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "strict_stdio.py"
            script.write_text(script_body, encoding="utf-8")
            spec = ServerSpec(
                name="strict-stdio",
                alias="strict_stdio",
                transport="stdio",
                command=sys.executable,
                args=("-u", str(script)),
            )
            client = StdioUpstreamClient(spec)
            try:
                errors: list[Exception] = []

                def _call_ok() -> None:
                    try:
                        client.call_tool("ok", {})
                    except Exception as exc:  # noqa: BLE001
                        errors.append(exc)

                threads = [threading.Thread(target=_call_ok) for _ in range(4)]
                for thread in threads:
                    thread.start()
                for thread in threads:
                    thread.join(timeout=5.0)
                self.assertEqual(errors, [])

                cancel = threading.Event()
                threading.Timer(0.15, cancel.set).start()
                t0 = time.monotonic()
                with self.assertRaises(UpstreamError) as cancel_ctx:
                    client.call_tool("sleep", {}, cancel_event=cancel)
                self.assertIn("cancelled", str(cancel_ctx.exception))
                self.assertLess(time.monotonic() - t0, 1.5)
            finally:
                client.close()

    def test_http_timeout_and_cancel_send_cancelled_notification(self) -> None:
        """Tell the HTTP upstream to stop a tools/call abandoned by deadline or cancellation."""
        st = _LifecycleState()
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            try:
                client.ensure_initialized()
                with self.assertRaises(UpstreamError):
                    client.call_tool("hang", {}, deadline=time.monotonic() + 0.3)
                self.assertTrue(st.wait_for(lambda: len(st.cancelled) == 1))
                self.assertEqual(st.cancelled, [(st.hung_ids[0], "sess-1")])

                cancel = threading.Event()
                errors: list[Exception] = []
                stream_hang = 2
                thread = _run_capturing(
                    lambda: client.call_tool("stream_hang", {}, cancel_event=cancel), errors
                )
                self.assertTrue(st.wait_for(lambda: len(st.hung_ids) == stream_hang))
                cancel.set()
                client.cancel_matching()
                thread.join(timeout=WAIT_SEC)
                self.assertEqual(len(errors), 1)
                self.assertIsInstance(errors[0], UpstreamError)
                self.assertIn("cancelled", str(errors[0]))
                # A cancel sent before headers arrive is repeated once they do.
                self.assertTrue(st.wait_for(lambda: len(st.cancelled) >= stream_hang))
                self.assertEqual(st.cancelled[1], (st.hung_ids[1], "sess-1"))
            finally:
                self.assertTrue(_close_drained(client))

    def test_http_cancel_before_headers_notifies_at_once(self) -> None:
        """Send notifications/cancelled on cancel even while the upstream withholds headers."""
        st = _LifecycleState()
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            try:
                client.ensure_initialized()
                cancel = threading.Event()
                errors: list[Exception] = []
                thread = _run_capturing(
                    lambda: client.call_tool(
                        "hang", {}, deadline=time.monotonic() + WAIT_SEC, cancel_event=cancel
                    ),
                    errors,
                )
                self.assertTrue(st.wait_for(lambda: len(st.hung_ids) == 1))
                cancel.set()
                client.cancel_matching()
                self.assertTrue(st.wait_for(lambda: len(st.cancelled) == 1, timeout=1.0))
                self.assertTrue(thread.is_alive())
                st.release.set()
                thread.join(timeout=WAIT_SEC)
                self.assertEqual(len(errors), 1)
                self.assertIn("cancelled", str(errors[0]))
                self.assertTrue(client.drain(time.monotonic() + WAIT_SEC))
                self.assertEqual(st.cancelled, [(st.hung_ids[0], "sess-1")])
            finally:
                self.assertTrue(_close_drained(client))

    def test_http_close_cancels_requests_of_a_stateless_upstream(self) -> None:
        """Cancel in-flight calls on close() when no session DELETE would end them."""
        st = _LifecycleState()
        st.issue_session = False
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            client.ensure_initialized()
            cancel = threading.Event()
            errors: list[Exception] = []
            threads = [
                _run_capturing(
                    lambda: client.call_tool("stream_hang", {}, cancel_event=cancel), errors
                ),
                _run_capturing(lambda: client.call_tool("stream_hang", {}), errors),
            ]
            calls = len(threads)
            self.assertTrue(st.wait_for(lambda: len(st.hung_ids) == calls))
            cancel.set()
            self.assertTrue(_close_drained(client))
            for thread in threads:
                thread.join(timeout=WAIT_SEC)
            self.assertTrue(client.drain(time.monotonic() + WAIT_SEC))
            self.assertEqual(len(errors), calls)
            # A cancel sent before headers arrive is repeated once they do.
            self.assertEqual(
                set(cast("list[int]", st.hung_ids)),
                {cast("int", request_id) for request_id, _ in st.cancelled},
            )
            self.assertEqual({session for _, session in st.cancelled}, {None})
            self.assertEqual(st.deleted, [])

    def test_http_late_reply_keeps_the_renewed_session(self) -> None:
        """Keep the renewed session when a reply sent under the expired one arrives late."""
        st = _LifecycleState()
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))

            def session_text(result: dict[str, object]) -> object:
                return cast("list[dict[str, object]]", result["content"])[0]["text"]

            client.ensure_initialized()
            held: list[dict[str, object]] = []
            errors: list[Exception] = []
            thread = _run_capturing(
                lambda: held.append(client.call_tool("held_session", {})), errors
            )
            self.assertTrue(st.wait_for(lambda: len(st.hung_ids) == 1))
            st.expired_sessions.add("sess-1")
            self.assertEqual(session_text(client.call_tool("session", {})), "sess-2")
            st.release.set()
            thread.join(timeout=WAIT_SEC)
            self.assertEqual(errors, [])
            self.assertEqual(session_text(held[0]), "sess-1")
            self.assertEqual(session_text(client.call_tool("session", {})), "sess-2")
            self.assertTrue(_close_drained(client))
            self.assertEqual(st.deleted, ["sess-2"])

    def test_http_sessions_issued_during_failed_or_closed_init_are_deleted(self) -> None:
        """DELETE every server-issued session the client drops, and stay closed after close()."""
        st = _LifecycleState()
        with _running_server(st) as url:
            st.init_gate = threading.Event()
            racing = HttpUpstreamClient(_http_spec(url))
            errors: list[Exception] = []
            thread = _run_capturing(racing.ensure_initialized, errors)
            self.assertTrue(st.init_entered.wait(timeout=WAIT_SEC))
            racing.close()
            self.assertEqual(st.deleted, [])
            st.init_gate.set()
            thread.join(timeout=WAIT_SEC)
            self.assertEqual(len(errors), 1)
            self.assertIsInstance(errors[0], UpstreamError)
            self.assertTrue(racing.drain(time.monotonic() + WAIT_SEC))
            self.assertEqual(st.deleted, ["sess-1"])

            st.initialized_status = 404
            failing = HttpUpstreamClient(_http_spec(url))
            with self.assertRaises(UpstreamError):
                failing.ensure_initialized()
            self.assertTrue(failing.drain(time.monotonic() + WAIT_SEC))
            self.assertEqual(st.deleted, ["sess-1", "sess-2"])
            st.initialized_status = 202

            closed = HttpUpstreamClient(_http_spec(url))
            closed.ensure_initialized()
            self.assertTrue(_close_drained(closed))
            self.assertEqual(st.deleted, ["sess-1", "sess-2", "sess-3"])
            init_count = st.init_count
            with self.assertRaises(UpstreamError):
                closed.ensure_initialized()
            with self.assertRaises(UpstreamError):
                closed.list_tools()
            self.assertEqual(st.init_count, init_count)

    def test_http_close_accepts_405_for_session_delete(self) -> None:
        """Treat a 405 DELETE reply as a server that keeps sessions, not a failure."""
        st = _LifecycleState()
        st.delete_status = 405
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            client.ensure_initialized()
            with mock.patch("sys.stderr", new_callable=io.StringIO) as stderr:
                self.assertTrue(_close_drained(client))
            self.assertEqual(st.deleted, ["sess-1"])
            self.assertEqual(stderr.getvalue(), "")

    def test_http_closed_init_returns_without_waiting_for_delete(self) -> None:
        """Return the closed error at once and leave the late session's DELETE to run detached."""
        st = _LifecycleState()
        st.init_gate = threading.Event()
        st.delete_gate = threading.Event()
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            errors: list[Exception] = []
            thread = _run_capturing(
                lambda: client.ensure_initialized(deadline=time.monotonic() + WAIT_SEC), errors
            )
            self.assertTrue(st.init_entered.wait(timeout=WAIT_SEC))
            client.close()
            st.init_gate.set()
            thread.join(timeout=1.0)
            self.assertFalse(thread.is_alive())
            self.assertEqual(len(errors), 1)
            self.assertIn("closed", str(errors[0]))
            self.assertTrue(st.wait_for(lambda: st.delete_started == ["sess-1"]))
            self.assertEqual(st.deleted, [])
            st.delete_gate.set()
            self.assertTrue(client.drain(time.monotonic() + WAIT_SEC))
            self.assertEqual(st.deleted, ["sess-1"])

    def test_http_best_effort_sends_are_bounded_per_client(self) -> None:
        """Drop sends past the per-client limit with a log line that names no session."""
        st = _LifecycleState()
        st.initialized_status = 404
        st.delete_gate = threading.Event()
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            with mock.patch("sys.stderr", new_callable=io.StringIO) as stderr:
                for _ in range(MAX_BEST_EFFORT_SENDS + 1):
                    with self.assertRaises(UpstreamError):
                        client.ensure_initialized()
            self.assertTrue(st.wait_for(lambda: len(st.delete_started) == MAX_BEST_EFFORT_SENDS))
            log = stderr.getvalue()
            self.assertEqual(
                log,
                f"mcp-codemode: upstream 'lc-http': dropped DELETE: "
                f"{MAX_BEST_EFFORT_SENDS} sends already pending\n",
            )
            st.delete_gate.set()
            self.assertTrue(client.drain(time.monotonic() + WAIT_SEC))
            self.assertEqual(len(st.deleted), MAX_BEST_EFFORT_SENDS)

    def test_http_failed_cleanup_thread_keeps_original_error(self) -> None:
        """Raise the handshake error, not the cleanup thread's start failure."""
        st = _LifecycleState()
        st.initialized_status = 404
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            caller = threading.current_thread()
            real_start = threading.Thread.start

            def refuse_on_caller(thread: threading.Thread) -> None:
                if threading.current_thread() is caller:
                    msg = "can't start new thread"
                    raise RuntimeError(msg)
                real_start(thread)

            with (
                mock.patch.object(threading.Thread, "start", refuse_on_caller),
                mock.patch("sys.stderr", new_callable=io.StringIO) as stderr,
                self.assertRaises(UpstreamError) as ctx,
            ):
                client.ensure_initialized()
            self.assertIn("404", str(ctx.exception))
            self.assertIn("dropped DELETE: can't start new thread", stderr.getvalue())
            self.assertFalse(client.has_pending_sends())

    def test_supervisor_close_all_waits_for_detached_sends(self) -> None:
        """Deliver a pending DELETE, even from an evicted client, before close_all() returns."""
        st = _LifecycleState()
        st.initialized_status = 404
        st.delete_gate = threading.Event()
        with _running_server(st) as url, tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "client": "test",
                        "servers": {"lc-http": {"transport": "http", "url": url}},
                    }
                ),
                encoding="utf-8",
            )
            supervisor = UpstreamSupervisor(load_manifest(manifest_path))
            with self.assertRaises(UpstreamError):
                supervisor.get_tools("lc-http")
            self.assertTrue(st.wait_for(lambda: st.delete_started == ["sess-1"]))
            supervisor.close_disabled({"lc-http": False})
            threading.Timer(0.3, st.delete_gate.set).start()
            supervisor.close_all()
            self.assertEqual(st.deleted, ["sess-1"])

    def _lifecycle_stdio_spec(self, root: Path, *extra: str) -> tuple[ServerSpec, Path]:
        script = root / "lifecycle_stdio.py"
        script.write_text(LIFECYCLE_STDIO_SCRIPT, encoding="utf-8")
        spawn_log = root / "spawns.log"
        spec = ServerSpec(
            name="lc-stdio",
            alias="lc_stdio",
            transport="stdio",
            command=sys.executable,
            args=("-u", str(script), str(spawn_log), *extra),
        )
        return spec, spawn_log

    def _stalling_stdio_spec(self, root: Path, *extra: str) -> tuple[ServerSpec, Path, Path]:
        script = root / "stalling_stdio.py"
        script.write_text(STALLING_STDIO_SCRIPT, encoding="utf-8")
        resume, received = root / "resume", root / "received.log"
        spec = ServerSpec(
            name="stall-stdio",
            alias="stall_stdio",
            transport="stdio",
            command=sys.executable,
            args=("-u", str(script), str(resume), str(received), *extra),
        )
        return spec, resume, received

    def test_stdio_callers_meet_deadlines_while_stdin_is_stalled(self) -> None:
        """Return by the deadline while stdin is full, and never send a request abandoned unsent."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, resume, received = self._stalling_stdio_spec(Path(tmp))
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                calls_to_stall: list[tuple[str, dict[str, object]]] = [
                    ("big", {"x": "a" * (1 << 21)}),
                    ("small", {}),
                ]
                for name, args in calls_to_stall:
                    errors: list[Exception] = []
                    deadline = time.monotonic() + 0.5
                    thread = _run_capturing(
                        lambda name=name, args=args, deadline=deadline: client.call_tool(
                            name, args, deadline=deadline
                        ),
                        errors,
                    )
                    thread.join(timeout=1.5)
                    self.assertFalse(thread.is_alive(), name)
                    self.assertEqual(len(errors), 1)
                    self.assertIn("timed out", str(errors[0]))
                resume.touch()
                client.call_tool("report", {})
                entries = [
                    cast("list[object]", json.loads(line))
                    for line in received.read_text(encoding="utf-8").splitlines()
                ]
                calls = {e[2]: e[1] for e in entries if e[0] == "tools/call"}
                self.assertEqual(list(calls), ["big", "report"])
                cancelled = [e[3] for e in entries if e[0] == "notifications/cancelled"]
                self.assertEqual(cancelled, [calls["big"]])
            finally:
                resume.touch()
                client.close()

    def test_http_initialize_is_never_cancelled(self) -> None:
        """Send no notifications/cancelled for an initialize that times out or is cancelled."""
        st = _LifecycleState()
        st.init_gate = threading.Event()
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            with self.assertRaises(UpstreamError) as ctx:
                client.ensure_initialized(deadline=time.monotonic() + 0.3)
            self.assertIn("timed out", str(ctx.exception))
            cancel = threading.Event()
            errors: list[Exception] = []
            thread = _run_capturing(lambda: client.ensure_initialized(cancel_event=cancel), errors)
            attempts = 2
            self.assertTrue(st.wait_for(lambda: st.init_count == attempts))
            cancel.set()
            client.cancel_matching()
            st.init_gate.set()
            thread.join(timeout=WAIT_SEC)
            self.assertEqual(len(errors), 1)
            self.assertIn("cancelled", str(errors[0]))
            self.assertTrue(_close_drained(client))
            self.assertEqual(st.cancelled, [])

    def test_stdio_initialize_is_never_cancelled(self) -> None:
        """Write no notifications/cancelled for an initialize that is cancelled or abandoned."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, _, received = self._stalling_stdio_spec(Path(tmp), "no-init-reply")

            def logged() -> list[object]:
                text = received.read_text(encoding="utf-8") if received.exists() else ""
                return [cast("list[object]", json.loads(line))[0] for line in text.splitlines()]

            client = StdioUpstreamClient(spec)
            try:
                for attempt, use_cancel_matching in enumerate((False, True), start=1):
                    cancel = threading.Event()
                    errors: list[Exception] = []
                    thread = _run_capturing(
                        lambda cancel=cancel: client.ensure_initialized(cancel_event=cancel), errors
                    )
                    end = time.monotonic() + WAIT_SEC
                    while logged().count("initialize") < attempt and time.monotonic() < end:
                        time.sleep(0.02)
                    cancel.set()
                    if use_cancel_matching:
                        client.cancel_matching()
                    thread.join(timeout=WAIT_SEC)
                    self.assertEqual(len(errors), 1)
                    self.assertIn("cancelled", str(errors[0]))
            finally:
                client.close()
            self.assertEqual(logged(), ["initialize", "initialize"])

    def test_stdio_full_backlog_drops_cancellations_and_fails_requests(self) -> None:
        """Log a dropped cancellation and fail a new request at once when the backlog is full."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, resume, received = self._stalling_stdio_spec(Path(tmp))
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                errors: list[Exception] = []
                big = _run_capturing(
                    lambda: client.call_tool(
                        "big", {"x": "a" * (1 << 21)}, deadline=time.monotonic() + 1.0
                    ),
                    errors,
                )
                time.sleep(0.2)
                with (
                    mock.patch("mcp_codemode.upstream.MAX_STDIO_WRITE_BACKLOG", 0),
                    mock.patch("sys.stderr", new_callable=io.StringIO) as stderr,
                ):
                    big.join(timeout=WAIT_SEC)
                    self.assertIn("timed out", str(errors[0]))
                    t0 = time.monotonic()
                    with self.assertRaises(UpstreamError) as ctx:
                        client.call_tool("small", {}, deadline=time.monotonic() + WAIT_SEC)
                    self.assertLess(time.monotonic() - t0, 0.5)
                self.assertIn("stdin writes already queued", str(ctx.exception))
                self.assertEqual(
                    stderr.getvalue(),
                    "mcp-codemode: upstream 'stall-stdio': dropped notifications/cancelled: "
                    "0 stdin writes already queued\n",
                )
                resume.touch()
                client.call_tool("report", {})
                entries = [
                    cast("list[object]", json.loads(line))
                    for line in received.read_text(encoding="utf-8").splitlines()
                ]
                calls = [e[2] for e in entries if e[0] == "tools/call"]
                self.assertEqual(calls, ["big", "report"])
                self.assertNotIn("notifications/cancelled", [e[0] for e in entries])
            finally:
                resume.touch()
                client.close()

    def test_stdio_timeout_sends_cancelled_and_closed_client_never_respawns(self) -> None:
        """Cancel a timed-out stdio request upstream, then refuse calls after close()."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, spawn_log = self._lifecycle_stdio_spec(Path(tmp))
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                with self.assertRaises(UpstreamError) as ctx:
                    client.call_tool("hang", {}, deadline=time.monotonic() + 0.3)
                self.assertIn("timed out", str(ctx.exception))
                report = client.call_tool("report", {})
                content = cast("list[dict[str, object]]", report["content"])
                ids = cast("dict[str, list[int]]", json.loads(str(content[0]["text"])))
                self.assertEqual(len(ids["hung"]), 1)
                self.assertEqual(ids["cancelled"], ids["hung"])
            finally:
                client.close()
            with self.assertRaises(UpstreamError):
                client.call_tool("report", {})
            with self.assertRaises(UpstreamError):
                client.list_tools()
            self.assertEqual(_spawn_count(spawn_log), 1)

    def test_stdio_failed_first_initialize_allows_respawn(self) -> None:
        """Respawn after a failed handshake instead of treating it as a permanent close."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, spawn_log = self._lifecycle_stdio_spec(Path(tmp), "fail-first")
            client = StdioUpstreamClient(spec)
            try:
                with self.assertRaises(UpstreamError) as ctx:
                    client.list_tools()
                self.assertIn("first init fails", str(ctx.exception))
                tools = client.list_tools()
                self.assertEqual([t["name"] for t in tools], ["hang"])
            finally:
                client.close()
            expected_spawns = 2
            self.assertEqual(_spawn_count(spawn_log), expected_spawns)

    def test_supervisor_close_all_rejects_calls_without_spawning(self) -> None:
        """Refuse call_tool and get_tools after close_all() and start no new client."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            spec, spawn_log = self._lifecycle_stdio_spec(root)
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "client": "test",
                        "servers": {
                            spec.name: {
                                "transport": "stdio",
                                "command": spec.command,
                                "args": list(spec.args),
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            supervisor = UpstreamSupervisor(load_manifest(manifest_path))
            self.assertEqual([t["name"] for t in supervisor.get_tools(spec.name)], ["hang"])
            supervisor.close_all()
            with self.assertRaises(UpstreamError):
                supervisor.call_tool(spec.name, "report", {})
            with self.assertRaises(UpstreamError):
                supervisor.get_tools(spec.name)
            with self.assertRaises(UpstreamError):
                supervisor.get_tools(spec.name, refresh=True)
            self.assertEqual(_spawn_count(spawn_log), 1)

    def test_supervisor_close_disabled_during_get_tools_caches_nothing(self) -> None:
        """Keep tools listed by an evicted client out of the cache."""
        st = _LifecycleState()
        with _running_server(st) as url, tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "client": "test",
                        "servers": {"lc-http": {"transport": "http", "url": url}},
                    }
                ),
                encoding="utf-8",
            )
            supervisor = UpstreamSupervisor(load_manifest(manifest_path))
            try:
                st.list_gate = threading.Event()
                errors: list[Exception] = []
                thread = _run_capturing(lambda: supervisor.get_tools("lc-http"), errors)
                self.assertTrue(st.list_entered.wait(timeout=WAIT_SEC))
                supervisor.close_disabled({"lc-http": False})
                st.list_gate.set()
                thread.join(timeout=WAIT_SEC)
                self.assertEqual(len(errors), 1)
                self.assertIsInstance(errors[0], UpstreamError)
                st.list_gate = None
                lists = st.list_count
                supervisor.get_tools("lc-http")
                self.assertEqual(st.list_count, lists + 1)

                # Eviction lands after list_tools returns but before the cache write.
                real_list_tools = HttpUpstreamClient.list_tools

                def list_then_disable(
                    client: HttpUpstreamClient,
                    deadline: float | None = None,
                    cancel_event: threading.Event | None = None,
                ) -> list[dict[str, object]]:
                    tools = real_list_tools(client, deadline=deadline, cancel_event=cancel_event)
                    supervisor.close_disabled({"lc-http": False})
                    return tools

                with mock.patch.object(HttpUpstreamClient, "list_tools", list_then_disable):
                    tools = supervisor.get_tools("lc-http", refresh=True)
                self.assertEqual([t["name"] for t in tools], ["a"])
                lists = st.list_count
                supervisor.get_tools("lc-http")
                self.assertEqual(st.list_count, lists + 1)
            finally:
                supervisor.close_all()

    def _http_supervisor(self, url: str, root: Path) -> UpstreamSupervisor:
        manifest_path = root / "manifest.json"
        manifest_path.write_text(
            json.dumps(
                {"client": "test", "servers": {"lc-http": {"transport": "http", "url": url}}}
            ),
            encoding="utf-8",
        )
        return UpstreamSupervisor(load_manifest(manifest_path))

    @staticmethod
    def _received_entries(received: Path) -> list[list[object]]:
        return [
            cast("list[object]", json.loads(line))
            for line in received.read_text(encoding="utf-8").splitlines()
        ]

    def test_http_cancel_that_overtakes_its_request_is_repeated(self) -> None:
        """Repeat a cancel sent before headers once they show the upstream has the request."""
        for closing in (False, True):
            with self.subTest(closing=closing):
                st = _LifecycleState()
                # Without a session, close() cancels each request instead of sending DELETE.
                st.issue_session = not closing
                st.upload_gate = threading.Event()
                with _running_server(st) as url:
                    client = HttpUpstreamClient(_http_spec(url))
                    client.ensure_initialized()
                    cancel = threading.Event()
                    errors: list[Exception] = []
                    thread = _run_capturing(
                        lambda client=client, cancel=cancel: client.call_tool(
                            "slow_upload", {}, cancel_event=cancel
                        ),
                        errors,
                    )
                    self.assertTrue(st.upload_entered.wait(timeout=WAIT_SEC))
                    if closing:
                        client.close()
                    else:
                        cancel.set()
                        client.cancel_matching()
                    self.assertTrue(st.wait_for(lambda st=st: len(st.received) == 1))
                    st.upload_gate.set()
                    thread.join(timeout=WAIT_SEC)
                    self.assertEqual(len(errors), 1)
                    self.assertIsInstance(errors[0], UpstreamError)
                    self.assertTrue(_close_drained(client))
                    call_ids = [msg_id for kind, msg_id in st.received if kind == "tools/call"]
                    self.assertEqual(len(call_ids), 1)
                    request_id = call_ids[0]
                    self.assertEqual(
                        st.received,
                        [
                            ("cancelled", request_id),
                            ("tools/call", request_id),
                            ("cancelled", request_id),
                        ],
                    )

    def test_http_request_after_close_never_reaches_the_upstream(self) -> None:
        """Refuse a POST that starts after close(), past the caller's initialized check."""
        st = _LifecycleState()
        with _running_server(st) as url:
            client = HttpUpstreamClient(_http_spec(url))
            real_ensure = client.ensure_initialized

            def ensure_then_close(
                deadline: float | None = None,
                cancel_event: threading.Event | None = None,
            ) -> None:
                real_ensure(deadline=deadline, cancel_event=cancel_event)
                client.close()

            with (
                mock.patch.object(client, "ensure_initialized", ensure_then_close),
                self.assertRaises(UpstreamError) as ctx,
            ):
                client.list_tools()
            self.assertIn("closed unexpectedly", str(ctx.exception))
            self.assertTrue(client.drain(time.monotonic() + WAIT_SEC))
            self.assertEqual(st.list_count, 0)

    def test_supervisor_close_all_waits_for_an_initialize_in_flight(self) -> None:
        """Deliver the DELETE for a session issued after close_all() closed its client."""
        for evict in (False, True):
            with self.subTest(evict=evict):
                st = _LifecycleState()
                st.init_gate = threading.Event()
                with _running_server(st) as url, tempfile.TemporaryDirectory() as tmp:
                    supervisor = self._http_supervisor(url, Path(tmp))
                    errors: list[Exception] = []
                    thread = _run_capturing(
                        lambda supervisor=supervisor: supervisor.get_tools("lc-http"), errors
                    )
                    self.assertTrue(st.init_entered.wait(timeout=WAIT_SEC))
                    if evict:
                        supervisor.close_disabled({"lc-http": False})
                    threading.Timer(0.3, st.init_gate.set).start()
                    supervisor.close_all()
                    self.assertEqual(st.deleted, ["sess-1"])
                    thread.join(timeout=WAIT_SEC)
                    self.assertEqual(len(errors), 1)

    def test_supervisor_close_all_waits_for_a_close_in_progress(self) -> None:
        """Deliver the DELETE of an eviction whose close() has not submitted it yet."""
        st = _LifecycleState()
        with _running_server(st) as url, tempfile.TemporaryDirectory() as tmp:
            supervisor = self._http_supervisor(url, Path(tmp))
            supervisor.get_tools("lc-http")
            real_submit = _BestEffortSends.submit
            entered, gate = threading.Event(), threading.Event()

            def gated_submit(
                sends: _BestEffortSends, what: str, target: Callable[..., None], *args: object
            ) -> None:
                if threading.current_thread().name == "evict":
                    entered.set()
                    gate.wait(timeout=WAIT_SEC)
                real_submit(sends, what, target, *args)

            with mock.patch.object(_BestEffortSends, "submit", gated_submit):
                evict = threading.Thread(
                    target=lambda: supervisor.close_disabled({"lc-http": False}), name="evict"
                )
                evict.start()
                self.assertTrue(entered.wait(timeout=WAIT_SEC))
                threading.Timer(0.3, gate.set).start()
                supervisor.close_all()
                self.assertEqual(st.deleted, ["sess-1"])
                evict.join(timeout=WAIT_SEC)

    def test_stdio_request_that_fails_to_encode_leaves_no_waiter(self) -> None:
        """Drop the reply slot of a request whose arguments cannot be encoded."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, _ = self._lifecycle_stdio_spec(Path(tmp))
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                with self.assertRaises(TypeError):
                    client.call_tool("report", {"x": {1}})
                self.assertEqual(client._pending, {})  # noqa: SLF001  # pyright: ignore[reportPrivateUsage]
                client.call_tool("report", {})
            finally:
                client.close()

    def test_stdio_cancel_matching_never_sends_a_request_queued_behind_a_stall(self) -> None:
        """Write neither a cancelled request still queued nor a cancel for it."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, resume, received = self._stalling_stdio_spec(Path(tmp))
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                errors: list[Exception] = []
                big = _run_capturing(
                    lambda: client.call_tool("big", {"x": "a" * (1 << 21)}), errors
                )
                time.sleep(0.2)
                cancel = threading.Event()
                queued = _run_capturing(
                    lambda: client.call_tool("queued", {}, cancel_event=cancel), errors
                )
                time.sleep(0.2)
                cancel.set()
                client.cancel_matching()
                queued.join(timeout=WAIT_SEC)
                self.assertEqual(len(errors), 1)
                self.assertIn("cancelled", str(errors[0]))
                resume.touch()
                big.join(timeout=WAIT_SEC)
                self.assertEqual(len(errors), 1)
                client.call_tool("report", {})
                entries = self._received_entries(received)
                calls = [e[2] for e in entries if e[0] == "tools/call"]
                self.assertEqual(calls, ["big", "report"])
                self.assertNotIn("notifications/cancelled", [e[0] for e in entries])
            finally:
                resume.touch()
                client.close()

    def test_stdio_close_never_sends_a_request_queued_behind_a_stall(self) -> None:
        """Skip a request still queued at close(), though stdin drains before SIGKILL."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, resume, received = self._stalling_stdio_spec(Path(tmp))
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                errors: list[Exception] = []
                threads = [
                    _run_capturing(lambda: client.call_tool("big", {"x": "a" * (1 << 21)}), errors)
                ]
                time.sleep(0.2)
                threads.append(_run_capturing(lambda: client.call_tool("queued", {}), errors))
                time.sleep(0.2)

                def resume_then_terminate(proc: subprocess.Popen[str], grace_sec: float) -> None:
                    resume.touch()
                    terminate_process_group(proc, grace_sec)

                with mock.patch(
                    "mcp_codemode.upstream.terminate_process_group",
                    side_effect=resume_then_terminate,
                ):
                    client.close()
                for thread in threads:
                    thread.join(timeout=WAIT_SEC)
                self.assertEqual(len(errors), len(threads))
                calls = [e[2] for e in self._received_entries(received) if e[0] == "tools/call"]
                self.assertEqual(calls, ["big"])
            finally:
                resume.touch()
                client.close()

    def test_stdio_close_delivers_queued_lines_and_eof_before_sigterm(self) -> None:
        """Close stdin after the queued cancel before signalling the process group."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, resume, received = self._stalling_stdio_spec(Path(tmp))
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                cancel = threading.Event()
                errors: list[Exception] = []
                thread = _run_capturing(
                    lambda: client.call_tool("small", {}, cancel_event=cancel), errors
                )
                time.sleep(0.2)
                cancel.set()
                client.cancel_matching()
                thread.join(timeout=WAIT_SEC)
                self.assertEqual(len(errors), 1)
                stdin_closed_at_sigterm: list[bool] = []

                def record_then_terminate(proc: subprocess.Popen[str], grace_sec: float) -> None:
                    stdin_closed_at_sigterm.append(proc.stdin is not None and proc.stdin.closed)
                    resume.touch()
                    terminate_process_group(proc, grace_sec)

                with mock.patch(
                    "mcp_codemode.upstream.terminate_process_group",
                    side_effect=record_then_terminate,
                ):
                    client.close()
                self.assertEqual(stdin_closed_at_sigterm, [True])
                entries = self._received_entries(received)
                small = [e[1] for e in entries if e[0] == "tools/call"]
                self.assertEqual(len(small), 1)
                cancelled = [e[3] for e in entries if e[0] == "notifications/cancelled"]
                self.assertEqual(cancelled, small)
            finally:
                resume.touch()
                client.close()

    def test_stdio_writer_stops_when_the_process_exits(self) -> None:
        """End the stdin writer on process exit, so a later send fails as closed."""
        with tempfile.TemporaryDirectory() as tmp:
            spec, resume, _ = self._stalling_stdio_spec(Path(tmp))
            resume.touch()
            client = StdioUpstreamClient(spec)
            try:
                client.ensure_initialized()
                proc = client._proc  # noqa: SLF001  # pyright: ignore[reportPrivateUsage]
                writer = client._writer  # noqa: SLF001  # pyright: ignore[reportPrivateUsage]
                if proc is None or writer is None:
                    self.fail("no running process after ensure_initialized()")
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=WAIT_SEC)
                t0 = time.monotonic()
                writer.join(WAIT_SEC)
                self.assertLess(time.monotonic() - t0, WAIT_SEC)
                with self.assertRaises(UpstreamError) as ctx:
                    client._send_raw({"jsonrpc": "2.0", "method": "ping"})  # noqa: SLF001  # pyright: ignore[reportPrivateUsage]
                self.assertIn("closed unexpectedly", str(ctx.exception))
            finally:
                client.close()
