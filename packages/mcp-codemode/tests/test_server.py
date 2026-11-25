# Copyright (c) 2026 Bad3r

"""End-to-end tests for the downstream Code Mode MCP server."""

from __future__ import annotations

import http.server
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from typing import TYPE_CHECKING, cast
from unittest import mock

from mcp_codemode._paths import resolve_node_bin, resolve_sandbox_script
from mcp_codemode.config import load_manifest, update_override_file, user_overrides_path
from mcp_codemode.sandbox import SandboxConfig, SandboxResult
from mcp_codemode.server import (
    RPC_INVALID_PARAMS,
    RPC_METHOD_NOT_FOUND,
    CodeModeServer,
    ToolDispatchError,
)

if TYPE_CHECKING:
    from collections.abc import Callable
    from typing import TextIO

    from mcp_codemode.sandbox import RpcHandler

WAIT_SEC = 5.0

STDIO_TOOL_SERVER = """
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        res = {"protocolVersion": "2025-03-26", "capabilities": {}}
    elif method == "tools/list":
        res = {
            "tools": [
                {"name": "snap", "description": "Take snapshot", "inputSchema": {"type": "object"}}
            ]
        }
    elif method == "tools/call":
        if msg["params"]["name"] == "snap":
            res = {
                "content": [
                    {"type": "text", "text": "captured"},
                    {"type": "image", "data": "ZmFrZQ==", "mimeType": "image/png"},
                ]
            }
        else:
            res = {"isError": True, "content": [{"type": "text", "text": "upstream failed"}]}
    else:
        continue
    print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": res}), flush=True)
"""


def _make_handler(header_value: str) -> type[http.server.BaseHTTPRequestHandler]:
    class HttpHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:  # noqa: A002
            del format, args

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", "0"))
            body = cast("dict[str, object]", json.loads(self.rfile.read(length).decode("utf-8")))
            if self.headers.get("X-Goog-Api-Key") != header_value:
                self.send_response(403)
                self.end_headers()
                return
            method = body.get("method")
            msg_id = body.get("id")
            if method == "initialize":
                result: dict[str, object] = {"protocolVersion": "2025-03-26", "capabilities": {}}
            elif method == "notifications/initialized":
                self.send_response(202)
                self.end_headers()
                return
            elif method == "tools/list":
                result = {
                    "tools": [
                        {
                            "name": "search_documents",
                            "description": "Search docs",
                            "inputSchema": {"type": "object"},
                        }
                    ]
                }
            else:
                raw_params = body.get("params")
                params = (
                    cast("dict[str, object]", raw_params) if isinstance(raw_params, dict) else {}
                )
                raw_args = params.get("arguments")
                args = cast("dict[str, object]", raw_args) if isinstance(raw_args, dict) else {}
                query = args.get("query", "")
                result = {"structuredContent": {"hits": [f"doc:{query}"]}}
            payload = json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": result}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    return HttpHandler


def _sandbox_config(timeout_sec: float = 10.0) -> SandboxConfig:
    return SandboxConfig(
        node_bin=resolve_node_bin(),
        bwrap_bin=None,
        sandbox_script=resolve_sandbox_script(),
        use_bwrap=False,
        timeout_sec=timeout_sec,
    )


def _empty_server(root: Path) -> CodeModeServer:
    manifest_path = root / "manifest.json"
    manifest_path.write_text(json.dumps({"client": "claude", "servers": {}}), encoding="utf-8")
    return CodeModeServer(load_manifest(manifest_path), _sandbox_config(), cwd=root)


def _tool_call(label: str, msg_id: int | None) -> dict[str, object]:
    msg: dict[str, object] = {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {"name": "search", "arguments": {"code": label}},
    }
    if msg_id is not None:
        msg["id"] = msg_id
    return msg


def _cancel(msg_id: int) -> dict[str, object]:
    return {"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": msg_id}}


def _reply_text(reply: dict[str, object]) -> str:
    result = reply.get("result")
    if not isinstance(result, dict):
        return ""
    blocks = cast("dict[str, object]", result).get("content")
    if not isinstance(blocks, list) or not blocks:
        return ""
    return str(cast("list[dict[str, object]]", blocks)[0].get("text", ""))


class _BlockingTools:
    """Stand-in for run_tool whose calls block until released or cancelled."""

    def __init__(self, labels: tuple[str, ...], *, released: tuple[str, ...] = ()) -> None:
        self.started = {label: threading.Event() for label in labels}
        self.finished = {label: threading.Event() for label in labels}
        self.release = {label: threading.Event() for label in released}
        self.cancelled: dict[str, bool] = {}

    def run_tool(
        self,
        tool_name: str,
        arguments: dict[str, object],
        *,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object]:
        del tool_name
        label = str(arguments["code"])
        self.started[label].set()
        gate = self.release.get(label) or cancel_event
        if gate is not None:
            gate.wait(timeout=WAIT_SEC)
        self.cancelled[label] = cancel_event is not None and cancel_event.is_set()
        self.finished[label].set()
        return {"content": [{"type": "text", "text": label}]}


class _StdioHarness:
    """Runs serve_stdio over pipes while a script thread writes requests; EOF follows the script."""

    def __init__(self, server: CodeModeServer) -> None:
        self._server = server
        self._replies: list[dict[str, object]] = []
        self._replies_cond = threading.Condition()
        self._writer: TextIO | None = None

    @property
    def replies(self) -> list[dict[str, object]]:
        with self._replies_cond:
            return list(self._replies)

    def send(self, payload: dict[str, object]) -> None:
        if self._writer is None:
            msg = "send() is only valid inside run()"
            raise RuntimeError(msg)
        self._writer.write(json.dumps(payload) + "\n")
        self._writer.flush()

    def wait_reply(self, predicate: Callable[[dict[str, object]], bool]) -> bool:
        with self._replies_cond:
            return self._replies_cond.wait_for(
                lambda: any(predicate(reply) for reply in self._replies), timeout=WAIT_SEC
            )

    def run(self, script: Callable[[_StdioHarness], None]) -> int:
        in_r, in_w = os.pipe()
        out_r, out_w = os.pipe()

        def _read() -> None:
            with os.fdopen(out_r, "r", encoding="utf-8") as reader:
                for line in reader:
                    if not line.strip():
                        continue
                    with self._replies_cond:
                        self._replies.append(cast("dict[str, object]", json.loads(line)))
                        self._replies_cond.notify_all()

        def _feed() -> None:
            with os.fdopen(in_w, "w", encoding="utf-8") as writer:
                self._writer = writer
                try:
                    script(self)
                finally:
                    self._writer = None

        reader_thread = threading.Thread(target=_read, daemon=True)
        feeder_thread = threading.Thread(target=_feed, daemon=True)
        reader_thread.start()
        feeder_thread.start()
        with (
            os.fdopen(in_r, "r", encoding="utf-8") as pipe_in,
            os.fdopen(out_w, "w", encoding="utf-8") as pipe_out,
            mock.patch.object(sys, "stdin", pipe_in),
            mock.patch.object(sys, "stdout", pipe_out),
        ):
            rc = self._server.serve_stdio()
        feeder_thread.join(timeout=WAIT_SEC)
        reader_thread.join(timeout=WAIT_SEC)
        if reader_thread.is_alive():
            msg = "reply reader did not reach EOF"
            raise RuntimeError(msg)
        return rc


class ServerTest(unittest.TestCase):
    """Covers downstream MCP methods, concurrency, cancellation, attachments, and live opt-in."""

    def _call_tool(
        self, server: CodeModeServer, msg_id: int, tool: str, code: str
    ) -> dict[str, object]:
        reply = server.handle_message(
            {
                "jsonrpc": "2.0",
                "id": msg_id,
                "method": "tools/call",
                "params": {"name": tool, "arguments": {"code": code}},
            }
        )
        if reply is None:
            self.fail("expected JSON-RPC reply for tools/call")
        return cast("dict[str, object]", reply["result"])

    def _verify_gateway(self, server: CodeModeServer, project_dir: Path, header_value: str) -> None:
        init_reply = server.handle_message({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
        if init_reply is None:
            self.fail("expected JSON-RPC reply for initialize")
        init_res = cast("dict[str, object]", init_reply["result"])
        srv_info = cast("dict[str, object]", init_res["serverInfo"])
        self.assertEqual(srv_info["name"], "mcp-codemode")

        tools_reply = server.handle_message({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        if tools_reply is None:
            self.fail("expected JSON-RPC reply for tools/list")
        tools_res = cast("dict[str, object]", tools_reply["result"])
        tools_list = cast("list[dict[str, object]]", tools_res["tools"])
        self.assertEqual([t["name"] for t in tools_list], ["search", "execute"])
        search_ann = cast("dict[str, object]", tools_list[0]["annotations"])
        self.assertTrue(search_ann["openWorldHint"])

        bad_method = server.handle_message({"jsonrpc": "2.0", "id": 20, "method": "unknown/method"})
        self.assertIsNotNone(bad_method)
        if bad_method is not None:
            self.assertEqual(
                cast("dict[str, object]", bad_method["error"])["code"], RPC_METHOD_NOT_FOUND
            )
        bad_params = server.handle_message(
            {"jsonrpc": "2.0", "id": 21, "method": "tools/call", "params": {}}
        )
        self.assertIsNotNone(bad_params)
        if bad_params is not None:
            self.assertEqual(
                cast("dict[str, object]", bad_params["error"])["code"], RPC_INVALID_PARAMS
            )

        blocked_code = (
            'async () => await codemode.google_developer_knowledge.search_documents({ query: "x" })'
        )
        blocked = self._call_tool(server, 3, "execute", blocked_code)
        self.assertTrue(blocked["isError"])
        blocked_blocks = cast("list[dict[str, object]]", blocked["content"])
        self.assertIn(
            "mcp-codemode enable google-developer-knowledge",
            str(blocked_blocks[0]["text"]),
        )

        update_override_file(
            user_overrides_path(),
            project_dir=project_dir,
            enable_names=["google-developer-knowledge"],
        )

        search_res = self._call_tool(
            server,
            4,
            "search",
            """
            async () => ({
              servers: await codemode.servers(),
              tools: await codemode.tools(),
              spec: await codemode.spec("google-developer-knowledge"),
            })
            """,
        )
        search_blocks = cast("list[dict[str, object]]", search_res["content"])
        discovery_bundle = cast("dict[str, object]", json.loads(str(search_blocks[0]["text"])))
        discovered = cast("dict[str, dict[str, object]]", discovery_bundle["tools"])
        self.assertTrue(discovered["google-developer-knowledge"]["enabled"])
        gdk_tools = cast(
            "list[dict[str, object]]", discovered["google-developer-knowledge"]["tools"]
        )
        self.assertEqual(gdk_tools[0]["name"], "search_documents")
        gdk_spec = cast("dict[str, object]", discovery_bundle["spec"])
        self.assertEqual(gdk_spec["server"], "google-developer-knowledge")

        exec_code = """
        async () => {
          const docs = await codemode.call(
            "google-developer-knowledge",
            "search_documents",
            { query: "mcp" },
          );
          const shot = await codemode.mock_browser.snap({});
          let caught = "";
          try {
            await codemode.mock_browser.fail({});
          } catch (err) {
            caught = err.message;
          }
          return { docs, shot, caught };
        }
        """
        exec_res = self._call_tool(server, 5, "execute", exec_code)
        blocks = cast("list[dict[str, object]]", exec_res["content"])
        self.assertEqual(blocks[0]["type"], "text")
        parsed = cast("dict[str, object]", json.loads(str(blocks[0]["text"])))
        self.assertEqual(parsed["docs"], {"hits": ["doc:mcp"]})
        self.assertIn("upstream failed", str(parsed["caught"]))
        self.assertEqual(blocks[1], {"type": "image", "data": "ZmFrZQ==", "mimeType": "image/png"})
        self.assertNotIn(header_value, str(blocks[0]["text"]))

    def test_end_to_end_gateway_and_hot_opt_in(self) -> None:
        """Multiplex stdio + HTTP upstreams, preserve image blocks, and hot-reload opt-in."""
        header_value = "dummy-value"
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _make_handler(header_value))
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()

        try:
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                data_dir = root / "data"
                state_dir = root / "state"
                project_dir = root / "proj"
                project_dir.mkdir()
                secret_file = data_dir / "google-developer-knowledge" / "api-key"
                secret_file.parent.mkdir(parents=True, exist_ok=True)
                secret_file.write_text(header_value + "\n", encoding="utf-8")

                stdio_script = root / "stdio_srv.py"
                stdio_script.write_text(STDIO_TOOL_SERVER, encoding="utf-8")

                manifest_path = root / "manifest.json"
                manifest_path.write_text(
                    json.dumps(
                        {
                            "client": "claude",
                            "servers": {
                                "mock-browser": {
                                    "transport": "stdio",
                                    "command": sys.executable,
                                    "args": ["-u", str(stdio_script)],
                                    "enabled": True,
                                    "primaryUse": "Take screenshots.",
                                },
                                "google-developer-knowledge": {
                                    "transport": "http",
                                    "url": f"http://127.0.0.1:{port}/mcp",
                                    "enabled": False,
                                    "secretHeader": {
                                        "name": "X-Goog-Api-Key",
                                        "relativePath": "google-developer-knowledge/api-key",
                                    },
                                    "primaryUse": "Search Google developer docs.",
                                },
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                manifest = load_manifest(manifest_path)
                sandbox_cfg = SandboxConfig(
                    node_bin=resolve_node_bin(),
                    bwrap_bin=None,
                    sandbox_script=resolve_sandbox_script(),
                    use_bwrap=False,
                    timeout_sec=15.0,
                )

                with mock.patch.dict(
                    os.environ,
                    {"XDG_DATA_HOME": str(data_dir), "XDG_STATE_HOME": str(state_dir)},
                    clear=False,
                ):
                    server = CodeModeServer(manifest, sandbox_cfg, cwd=project_dir)
                    try:
                        self._verify_gateway(server, project_dir, header_value)
                    finally:
                        server.supervisor.close_all()
        finally:
            srv.shutdown()
            srv.server_close()

    def test_missing_secret_isolated_and_slow_timeout_is_prompt(self) -> None:
        """Isolate missing secrets, time out promptly on slow upstream, and keep gateway alive."""
        slow_stdio = """
import json, sys, time
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        res = {"protocolVersion": "2025-03-26", "capabilities": {}}
    elif method == "tools/list":
        res = {
            "tools": [
                {"name": "slow", "description": "Slow", "inputSchema": {"type": "object"}}
            ]
        }
    elif method == "tools/call":
        time.sleep(3.0)
        res = {"content": [{"type": "text", "text": "done"}]}
    else:
        continue
    print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": res}), flush=True)
"""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            data_dir = root / "data"
            state_dir = root / "state"
            stdio_script = root / "slow_stdio.py"
            stdio_script.write_text(slow_stdio, encoding="utf-8")
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "client": "claude",
                        "servers": {
                            "cloudflare-api": {
                                "transport": "http",
                                "url": "http://127.0.0.1:9/mcp",
                                "enabled": True,
                                "secretHeader": {
                                    "name": "Authorization",
                                    "prefix": "Bearer ",
                                    "relativePath": "cloudflare/missing",
                                },
                            },
                            "slow-stdio": {
                                "transport": "stdio",
                                "command": sys.executable,
                                "args": ["-u", str(stdio_script)],
                                "enabled": True,
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )
            manifest = load_manifest(manifest_path)
            sandbox_cfg = SandboxConfig(
                node_bin=resolve_node_bin(),
                bwrap_bin=None,
                sandbox_script=resolve_sandbox_script(),
                use_bwrap=False,
                timeout_sec=0.4,
            )
            with mock.patch.dict(
                os.environ,
                {"XDG_DATA_HOME": str(data_dir), "XDG_STATE_HOME": str(state_dir)},
                clear=False,
            ):
                server = CodeModeServer(manifest, sandbox_cfg, cwd=root)
                try:
                    search_res = self._call_tool(
                        server, 1, "search", "async () => await codemode.tools()"
                    )
                    blocks = cast("list[dict[str, object]]", search_res["content"])
                    discovered = cast(
                        "dict[str, dict[str, object]]", json.loads(str(blocks[0]["text"]))
                    )
                    self.assertEqual(
                        cast("list[dict[str, object]]", discovered["slow-stdio"]["tools"])[0][
                            "name"
                        ],
                        "slow",
                    )
                    self.assertIn("error", discovered["cloudflare-api"])

                    t0 = time.monotonic()
                    timed_out = self._call_tool(
                        server,
                        2,
                        "execute",
                        "async () => await codemode.slow_stdio.slow({})",
                    )
                    elapsed = time.monotonic() - t0
                    self.assertTrue(timed_out["isError"])
                    timeout_blocks = cast("list[dict[str, object]]", timed_out["content"])
                    self.assertIn("timed out", str(timeout_blocks[0]["text"]))
                    self.assertLess(elapsed, 2.0)

                    ping = server.handle_message({"jsonrpc": "2.0", "id": 3, "method": "ping"})
                    self.assertEqual(ping, {"jsonrpc": "2.0", "id": 3, "result": {}})
                finally:
                    server.supervisor.close_all()

    def test_tools_call_rejects_non_object_arguments(self) -> None:
        """Answer tools/call with non-object arguments with an invalid-params error."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps({"client": "claude", "servers": {}}), encoding="utf-8"
            )
            server = CodeModeServer(load_manifest(manifest_path), _sandbox_config(), cwd=root)
            for tool in ("search", "execute"):
                with self.subTest(tool=tool):
                    reply = server.handle_message(
                        {
                            "jsonrpc": "2.0",
                            "id": 1,
                            "method": "tools/call",
                            "params": {"name": tool, "arguments": "async () => 1"},
                        }
                    )
                    if reply is None:
                        self.fail("expected JSON-RPC reply for tools/call with string arguments")
                    error = cast("dict[str, object]", reply["error"])
                    self.assertEqual(error["code"], RPC_INVALID_PARAMS)
                    self.assertEqual(
                        error["message"],
                        f"tools/call codemode.{tool}: 'arguments' must be an object, got string",
                    )

    def test_tools_call_reports_unknown_tool_before_arguments(self) -> None:
        """Name an unknown tool as unknown whatever its arguments are."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps({"client": "claude", "servers": {}}), encoding="utf-8"
            )
            server = CodeModeServer(load_manifest(manifest_path), _sandbox_config(), cwd=root)
            for arguments in ("async () => 1", {"code": "1"}):
                with self.subTest(arguments=arguments):
                    reply = server.handle_message(
                        {
                            "jsonrpc": "2.0",
                            "id": 1,
                            "method": "tools/call",
                            "params": {"name": "nope", "arguments": arguments},
                        }
                    )
                    self.assertEqual(
                        reply,
                        {
                            "jsonrpc": "2.0",
                            "id": 1,
                            "error": {
                                "code": RPC_INVALID_PARAMS,
                                "message": "Unknown tool: nope",
                            },
                        },
                    )

    def test_call_tool_rejects_non_object_arguments(self) -> None:
        """Reject non-object call_tool args at the host, independent of the sandbox check."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "client": "claude",
                        "servers": {
                            "mock-browser": {
                                "transport": "stdio",
                                "command": sys.executable,
                                "args": ["-c", "pass"],
                                "enabled": True,
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            server = CodeModeServer(load_manifest(manifest_path), _sandbox_config(), cwd=root)
            errors: dict[str, str] = {}

            def fake_run_sandbox(*, rpc_handler: RpcHandler, **_: object) -> SandboxResult:
                deadline = time.monotonic() + WAIT_SEC
                cancel = threading.Event()
                target: dict[str, object] = {"server": "mock-browser", "tool": "snap"}
                cases: dict[str, dict[str, object]] = {
                    "string": {"args": "owner/repo"},
                    "array": {"args": ["owner/repo"]},
                    "null": {"args": None},
                    "undefined": {},
                }
                for kind, extra in cases.items():
                    try:
                        rpc_handler("call_tool", {**target, **extra}, deadline, cancel)
                        errors[kind] = "accepted"
                    except ToolDispatchError as exc:
                        errors[kind] = str(exc)
                rpc_handler("call_tool", {**target, "args": {}}, deadline, cancel)
                return SandboxResult(value=None)

            upstream_ok = {"content": [{"type": "text", "text": "ok"}]}
            with (
                mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(root / "state")}, clear=False),
                mock.patch("mcp_codemode.server.run_sandbox", fake_run_sandbox),
                mock.patch.object(
                    server.supervisor, "call_tool", return_value=upstream_ok
                ) as call_tool,
            ):
                try:
                    res = self._call_tool(server, 1, "execute", "async () => 1")
                finally:
                    server.supervisor.close_all()

            self.assertNotIn("isError", res)
            self.assertEqual(
                errors,
                {
                    kind: f"mock-browser.snap: arguments must be an object, got {kind}"
                    for kind in ("string", "array", "null", "undefined")
                },
            )
            call_tool.assert_called_once()
            self.assertEqual(call_tool.call_args.args, ("mock-browser", "snap", {}))

    def test_serve_stdio_concurrent_ping_and_cancellation(self) -> None:
        """Keep stdin open to prove notifications/cancelled (not EOF) aborts tools/call."""
        hang_code = "async () => new Promise(() => {})"
        hang_returned = threading.Event()
        later_id = 12
        observed: dict[str, bool] = {}

        def script(harness: _StdioHarness) -> None:
            harness.send(_tool_call(hang_code, 10))
            harness.send(
                {
                    "jsonrpc": "2.0",
                    "id": ["unhashable"],
                    "method": "tools/call",
                    "params": {"name": "search", "arguments": {"code": "1 + 1"}},
                }
            )
            harness.send({"jsonrpc": "2.0", "id": 11, "method": "ping"})
            harness.send(_cancel(10))
            # Keep stdin open until cancellation finishes so EOF cannot mask it.
            observed["cancelled_before_eof"] = hang_returned.wait(timeout=2.5)
            harness.send({"jsonrpc": "2.0", "id": later_id, "method": "ping"})
            harness.wait_reply(lambda reply: reply.get("id") == later_id)

        with tempfile.TemporaryDirectory() as tmp:
            server = _empty_server(Path(tmp))
            real_run_tool = server.run_tool

            def _tracked_run_tool(
                tool_name: str,
                arguments: dict[str, object],
                *,
                cancel_event: threading.Event | None = None,
            ) -> dict[str, object]:
                try:
                    return real_run_tool(tool_name, arguments, cancel_event=cancel_event)
                finally:
                    if arguments.get("code") == hang_code:
                        hang_returned.set()

            harness = _StdioHarness(server)
            t0 = time.monotonic()
            with mock.patch.object(server, "run_tool", _tracked_run_tool):
                rc = harness.run(script)
            elapsed = time.monotonic() - t0

        self.assertEqual(rc, 0)
        self.assertEqual(observed, {"cancelled_before_eof": True})
        self.assertLess(elapsed, 3.0)
        int_replies = {
            reply["id"]: reply.get("result")
            for reply in harness.replies
            if isinstance(reply.get("id"), int)
        }
        self.assertEqual(int_replies, {11: {}, later_id: {}})

    def test_serve_stdio_rejects_calls_past_queue_limit(self) -> None:
        """Answer a tools/call with the queue-limit error once workers and queue are full."""
        tools = _BlockingTools(("running", "queued", "overflow"))
        overflow_id = 3

        def script(harness: _StdioHarness) -> None:
            harness.send(_tool_call("running", 1))
            if tools.started["running"].wait(timeout=WAIT_SEC):
                harness.send(_tool_call("queued", 2))
                harness.send(_tool_call("overflow", overflow_id))
                harness.wait_reply(lambda reply: reply.get("id") == overflow_id)

        with (
            tempfile.TemporaryDirectory() as tmp,
            mock.patch.multiple(
                "mcp_codemode.server", MAX_CONCURRENT_REQUESTS=1, MAX_PENDING_REQUESTS=1
            ),
        ):
            server = _empty_server(Path(tmp))
            harness = _StdioHarness(server)
            with mock.patch.object(server, "run_tool", tools.run_tool):
                rc = harness.run(script)

        self.assertEqual(rc, 0)
        self.assertTrue(tools.started["running"].is_set())
        self.assertFalse(tools.started["overflow"].is_set())
        limit_replies = [
            reply
            for reply in harness.replies
            if "Too many queued tool calls (limit: 1)"
            in str(cast("dict[str, object]", reply.get("error", {})).get("message", ""))
        ]
        self.assertEqual([reply["id"] for reply in limit_replies], [overflow_id])

    def test_serve_stdio_cancel_reaches_every_call_sharing_an_id(self) -> None:
        """One notifications/cancelled cancels every in-flight call under that request ID."""
        labels = ("first", "second")
        tools = _BlockingTools(labels)
        observed: dict[str, bool] = {}

        def script(harness: _StdioHarness) -> None:
            for label in labels:
                harness.send(_tool_call(label, 7))
            if all(tools.started[label].wait(timeout=WAIT_SEC) for label in labels):
                harness.send(_cancel(7))
                observed["finished_before_eof"] = all(
                    tools.finished[label].wait(timeout=WAIT_SEC) for label in labels
                )

        with tempfile.TemporaryDirectory() as tmp:
            server = _empty_server(Path(tmp))
            harness = _StdioHarness(server)
            with mock.patch.object(server, "run_tool", tools.run_tool):
                rc = harness.run(script)

        self.assertEqual(rc, 0)
        self.assertEqual(observed, {"finished_before_eof": True})
        self.assertEqual(tools.cancelled, {"first": True, "second": True})
        self.assertEqual(harness.replies, [])

    def test_serve_stdio_cancel_survives_finished_sibling(self) -> None:
        """A finished call under a shared request ID leaves its sibling cancellable."""
        tools = _BlockingTools(("done", "pending", "later"), released=("done", "later"))
        observed: dict[str, bool] = {}

        def script(harness: _StdioHarness) -> None:
            harness.send(_tool_call("done", 8))
            harness.send(_tool_call("pending", 8))
            if not all(
                tools.started[label].wait(timeout=WAIT_SEC) for label in ("done", "pending")
            ):
                return
            tools.release["done"].set()
            if harness.wait_reply(lambda reply: _reply_text(reply) == "done"):
                harness.send(_cancel(8))
                observed["pending_before_eof"] = tools.finished["pending"].wait(timeout=WAIT_SEC)
                tools.release["later"].set()
                harness.send(_tool_call("later", 8))
                harness.wait_reply(lambda reply: _reply_text(reply) == "later")

        with tempfile.TemporaryDirectory() as tmp:
            server = _empty_server(Path(tmp))
            harness = _StdioHarness(server)
            with mock.patch.object(server, "run_tool", tools.run_tool):
                rc = harness.run(script)

        self.assertEqual(rc, 0)
        self.assertEqual(observed, {"pending_before_eof": True})
        self.assertEqual(tools.cancelled, {"done": False, "pending": True, "later": False})
        self.assertEqual([_reply_text(reply) for reply in harness.replies], ["done", "later"])

    def test_serve_stdio_shutdown_cancel_still_replies(self) -> None:
        """Closing stdin cancels an in-flight tools/call and still answers its request ID."""
        tools = _BlockingTools(("inflight",))

        def script(harness: _StdioHarness) -> None:
            harness.send(_tool_call("inflight", 9))
            tools.started["inflight"].wait(timeout=WAIT_SEC)

        with tempfile.TemporaryDirectory() as tmp:
            server = _empty_server(Path(tmp))
            harness = _StdioHarness(server)
            with mock.patch.object(server, "run_tool", tools.run_tool):
                rc = harness.run(script)

        self.assertEqual(rc, 0)
        self.assertEqual(tools.cancelled, {"inflight": True})
        self.assertEqual(
            [(reply.get("id"), _reply_text(reply)) for reply in harness.replies], [(9, "inflight")]
        )

    def test_serve_stdio_shutdown_cancels_call_without_id(self) -> None:
        """Closing stdin cancels an in-flight tools/call that carries no request ID."""
        tools = _BlockingTools(("orphan",))

        def script(harness: _StdioHarness) -> None:
            harness.send(_tool_call("orphan", None))
            tools.started["orphan"].wait(timeout=WAIT_SEC)

        with tempfile.TemporaryDirectory() as tmp:
            server = _empty_server(Path(tmp))
            harness = _StdioHarness(server)
            with mock.patch.object(server, "run_tool", tools.run_tool):
                rc = harness.run(script)

        self.assertEqual(rc, 0)
        self.assertTrue(tools.started["orphan"].is_set())
        self.assertTrue(tools.finished["orphan"].is_set())
        self.assertEqual(tools.cancelled, {"orphan": True})
        self.assertEqual(harness.replies, [])
