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
from typing import cast
from unittest import mock

from mcp_codemode._paths import resolve_node_bin, resolve_sandbox_script
from mcp_codemode.config import load_manifest, update_override_file, user_overrides_path
from mcp_codemode.sandbox import SandboxConfig
from mcp_codemode.server import (
    RPC_INVALID_PARAMS,
    RPC_METHOD_NOT_FOUND,
    CodeModeServer,
)

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
            reply = server.handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "tools/call",
                    "params": {"name": "search", "arguments": "async () => 1"},
                }
            )
        if reply is None:
            self.fail("expected JSON-RPC reply for tools/call with string arguments")
        error = cast("dict[str, object]", reply["error"])
        self.assertEqual(error["code"], RPC_INVALID_PARAMS)
        self.assertIn("'arguments' must be an object, got string", str(error["message"]))

    def test_call_tool_rejects_non_object_arguments(self) -> None:
        """Reject non-object sandbox arguments before the upstream; omitted ones still send {}."""
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
            code = """
            async () => {
              const errors = {};
              const attempts = {
                string: () => codemode.mock_browser.snap("owner/repo"),
                array: () => codemode.call("mock-browser", "snap", ["owner/repo"]),
                null: () => codemode.mock_browser.snap(null),
              };
              for (const [kind, attempt] of Object.entries(attempts)) {
                try {
                  await attempt();
                  errors[kind] = "accepted";
                } catch (err) {
                  errors[kind] = err.message;
                }
              }
              const omitted = await codemode.mock_browser.snap();
              return { errors, omitted };
            }
            """
            upstream_ok = {"content": [{"type": "text", "text": "ok"}]}
            with (
                mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(root / "state")}, clear=False),
                mock.patch.object(
                    server.supervisor, "call_tool", return_value=upstream_ok
                ) as call_tool,
            ):
                try:
                    res = self._call_tool(server, 1, "execute", code)
                finally:
                    server.supervisor.close_all()

            blocks = cast("list[dict[str, object]]", res["content"])
            parsed = cast("dict[str, object]", json.loads(str(blocks[0]["text"])))
            errors = cast("dict[str, str]", parsed["errors"])
            for kind in ("string", "array", "null"):
                self.assertIn(
                    f"mock-browser.snap: arguments must be an object, got {kind}", errors[kind]
                )
            self.assertEqual(parsed["omitted"], "ok")
            call_tool.assert_called_once()
            self.assertEqual(call_tool.call_args.args, ("mock-browser", "snap", {}))

    def test_serve_stdio_concurrent_ping_and_cancellation(self) -> None:
        """Keep stdin open to prove notifications/cancelled (not EOF) aborts tools/call."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps({"client": "claude", "servers": {}}),
                encoding="utf-8",
            )
            manifest = load_manifest(manifest_path)
            sandbox_cfg = SandboxConfig(
                node_bin=resolve_node_bin(),
                bwrap_bin=None,
                sandbox_script=resolve_sandbox_script(),
                use_bwrap=False,
                timeout_sec=10.0,
            )
            server = CodeModeServer(manifest, sandbox_cfg, cwd=root)

            in_r, in_w = os.pipe()
            out_r, out_w = os.pipe()
            replies: list[dict[str, object]] = []
            cancel_done = threading.Event()

            cancel_req_id = 10

            def _read_replies() -> None:
                with os.fdopen(out_r, "r", encoding="utf-8") as reader:
                    for line in reader:
                        if not line.strip():
                            continue
                        parsed = cast("dict[str, object]", json.loads(line))
                        replies.append(parsed)
                        if parsed.get("id") == cancel_req_id:
                            cancel_done.set()

            reader_thread = threading.Thread(target=_read_replies, daemon=True)
            reader_thread.start()

            def _feed_stdin() -> None:
                with os.fdopen(in_w, "w", encoding="utf-8") as writer:
                    for payload in (
                        {
                            "jsonrpc": "2.0",
                            "id": 10,
                            "method": "tools/call",
                            "params": {
                                "name": "search",
                                "arguments": {"code": "async () => new Promise(() => {})"},
                            },
                        },
                        {
                            "jsonrpc": "2.0",
                            "id": ["unhashable"],
                            "method": "tools/call",
                            "params": {"name": "search", "arguments": {"code": "1 + 1"}},
                        },
                        {"jsonrpc": "2.0", "id": 11, "method": "ping"},
                        {
                            "jsonrpc": "2.0",
                            "method": "notifications/cancelled",
                            "params": {"requestId": 10},
                        },
                    ):
                        writer.write(json.dumps(payload) + "\n")
                        writer.flush()
                    # Keep stdin open until cancellation finishes so EOF cannot mask it.
                    cancel_done.wait(timeout=4.0)

            feeder = threading.Thread(target=_feed_stdin, daemon=True)
            feeder.start()

            t0 = time.monotonic()
            with (
                os.fdopen(in_r, "r", encoding="utf-8") as pipe_in,
                os.fdopen(out_w, "w", encoding="utf-8") as pipe_out,
                mock.patch.object(sys, "stdin", pipe_in),
                mock.patch.object(sys, "stdout", pipe_out),
            ):
                rc = server.serve_stdio()
            elapsed = time.monotonic() - t0
            feeder.join(timeout=2.0)
            reader_thread.join(timeout=2.0)

            self.assertEqual(rc, 0)
            self.assertTrue(cancel_done.is_set())
            self.assertLess(elapsed, 3.0)

            by_id = {
                reply["id"]: reply for reply in replies if isinstance(reply.get("id"), (int, str))
            }
            self.assertEqual(by_id[11]["result"], {})
            cancelled_res = cast("dict[str, object]", by_id[10]["result"])
            self.assertTrue(cancelled_res["isError"])
            cancelled_blocks = cast("list[dict[str, object]]", cancelled_res["content"])
            self.assertIn("cancelled", str(cancelled_blocks[0]["text"]))
