# Copyright (c) 2026 Bad3r

"""Tests for stdio and Streamable HTTP upstream MCP clients."""

from __future__ import annotations

import gzip
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

from mcp_codemode.config import SecretHeader, ServerSpec, load_manifest
from mcp_codemode.upstream import (
    HttpUpstreamClient,
    StdioUpstreamClient,
    UpstreamError,
    UpstreamSupervisor,
)

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
            payload = {"echoed": args.get("msg"), "env": os.environ.get("MOCK_ENV", "")}
            reply = {"content": [{"type": "text", "text": json.dumps(payload)}]}
        else:
            total = str(args.get("a", 0) + args.get("b", 0))
            reply = {"content": [{"type": "text", "text": total}]}
    else:
        continue
    print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": reply}), flush=True)
"""


class UpstreamTest(unittest.TestCase):
    """Covers HTTP SSE/gzip/session/secret headers and stdio pagination/teardown."""

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
                    client.close()

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
                    client.close()
                self.assertTrue(received_auth)
                self.assertTrue(all(h == "Bearer dummy-value" for h in received_auth))
        finally:
            srv.shutdown()
            srv.server_close()

    def test_stdio_upstream_and_supervisor(self) -> None:
        """Paginate stdio tools, forward manifest env, and close cleanly."""
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
            finally:
                supervisor.close_all()
