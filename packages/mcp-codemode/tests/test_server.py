# Copyright (c) 2026 Bad3r

"""End-to-end tests for the downstream Code Mode MCP server."""

from __future__ import annotations

import http.server
import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from typing import cast
from unittest import mock

from mcp_codemode._paths import resolve_node_bin, resolve_sandbox_script
from mcp_codemode.config import PROJECT_CONFIG_NAME, load_manifest, update_override_file
from mcp_codemode.server import CodeModeServer, build_sandbox_config

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


class ServerTest(unittest.TestCase):
    """Covers downstream initialize, tools/list, search, execute, attachments, and live opt-in."""

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
            project_dir / PROJECT_CONFIG_NAME,
            enable_names=["google-developer-knowledge"],
        )

        search_res = self._call_tool(server, 4, "search", "async () => await codemode.tools()")
        search_blocks = cast("list[dict[str, object]]", search_res["content"])
        discovered = cast("dict[str, dict[str, object]]", json.loads(str(search_blocks[0]["text"])))
        self.assertTrue(discovered["google-developer-knowledge"]["enabled"])
        gdk_tools = cast(
            "list[dict[str, object]]", discovered["google-developer-knowledge"]["tools"]
        )
        self.assertEqual(gdk_tools[0]["name"], "search_documents")

        exec_code = """
        async () => {
          const docs = await codemode.google_developer_knowledge.search_documents({ query: "mcp" });
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
                sandbox_cfg = build_sandbox_config(
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
