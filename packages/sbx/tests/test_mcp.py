# Copyright (c) 2026 Bad3r
"""The MCP front end of sbx against the fake backend of the core tests."""

import io
import json
import os
import threading
import time
import unittest
from typing import TYPE_CHECKING, Any, cast
from unittest import mock

from sbx import mcp
from sbx.cli import build_parser
from sbx.core import SbxError

from . import test_core

if TYPE_CHECKING:
    import argparse

SAMPLES: dict[str, object] = {
    "base": "nixos",
    "flavour": "nixos",
    "name": "probe",
    "net": "none",
    "mem": "2G",
    "cpus": 2,
    "ttl": "30m",
    "in": ["/work/a", "/work/b"],
    "out": ["/root/report.txt"],
    "to": "/work",
    "timeout": "5m",
    "agent": True,
    "command": ["sh", "-c", "true"],
    "source": "probe:/root/x",
    "destination": "/work",
    "mine": True,
    "expired": True,
    "ocr": True,
    "dry_run": True,
}
# destroy takes exactly one of these.
EXCLUSIVE = ("mine", "expired")


class CommandLineTest(unittest.TestCase):
    """Tool arguments become verb arguments the CLI parser accepts."""

    def test_every_tool_parses(self) -> None:
        """Each tool with every argument set yields a valid command line."""
        for tool in mcp.TOOLS:
            names = [param.name for param in tool.params]
            if tool.name == "destroy":
                names = [name for name in names if name not in EXCLUSIVE]
            arguments = {name: SAMPLES[name] for name in names}
            with self.subTest(tool=tool.name):
                argv, _command = tool.command_line(arguments)
                args = build_parser().parse_args(argv)
                self.assertEqual(args.verb, tool.verb[0])
                schema = cast("dict[str, Any]", tool.definition()["inputSchema"])
                self.assertFalse(schema["additionalProperties"])
                self.assertLessEqual(set(schema["required"]), set(schema["properties"]))

    def test_mapping(self) -> None:
        """Options take the = form, repeat per item, and the command stays apart."""
        argv, command = mcp.TOOLS_BY_NAME["exec"].command_line(
            {"name": "a", "timeout": "5m", "agent": True, "command": ["sh", "-c", "x -- y"]}
        )
        self.assertEqual(argv, ["exec", "--timeout=5m", "--agent", "a"])
        self.assertEqual(command, ["sh", "-c", "x -- y"])
        argv, _ = mcp.TOOLS_BY_NAME["run"].command_line(
            {"base": "nixos", "name": "-x", "in": ["a", "b"], "ttl": None, "command": ["id"]}
        )
        self.assertEqual(argv, ["run", "--name=-x", "--in=a", "--in=b", "nixos"])
        args = build_parser().parse_args(argv)
        self.assertEqual((args.name, args.inputs), ("-x", ["a", "b"]))
        argv, _ = mcp.TOOLS_BY_NAME["base_build"].command_line({"flavour": "nixos"})
        self.assertEqual(argv, ["base", "build", "nixos"])

    def test_refusals(self) -> None:
        """Malformed arguments are usage errors, and none becomes an option."""
        cases: list[tuple[str, object]] = [
            ("destroy", {"name": "--mine"}),
            ("cp", {"source": "-r"}),
            ("info", {"name": "a", "verbose": True}),
            ("info", {}),
            ("info", ["a"]),
            ("create", {"base": "nixos", "cpus": True}),
            ("create", {"base": "nixos", "cpus": "2"}),
            ("exec", {"name": "a", "command": "id"}),
            ("exec", {"name": "a", "command": []}),
            ("list", {"mine": "yes"}),
        ]
        for tool, arguments in cases:
            with self.subTest(tool=tool, arguments=arguments):
                with self.assertRaises(SbxError) as raised:
                    mcp.TOOLS_BY_NAME[tool].command_line(arguments)
                self.assertEqual(raised.exception.code, "usage")

    def test_session(self) -> None:
        """Codex names its thread per call; otherwise the environment decides."""
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "s1"}):
            self.assertEqual(mcp.session_of({"threadId": "t1"}), "codex:t1")
            self.assertEqual(mcp.session_of({"threadId": ""}), "claude:s1")
            self.assertEqual(mcp.session_of(None), "claude:s1")


class ServerTest(unittest.TestCase):
    """The protocol, over the core tests' fake backend."""

    def setUp(self) -> None:
        """Borrow the state directory, stub tools, and backend of the core tests."""
        self.core = test_core.SandboxesTest("test_parsers")
        self.core.setUp()
        self.addCleanup(self.core.doCleanups)
        self.sessions: list[str | None] = []

    def exchange(self, *messages: object) -> dict[object, dict[str, Any]]:
        """Send raw messages and return the responses by id."""

        def open_sandboxes(session: str | None) -> Any:  # noqa: ANN401
            self.sessions.append(session)
            return self.core.sandboxes(session)

        output = io.BytesIO()
        server = mcp.Server(open_sandboxes, output, "0.0.0")
        lines = [m if isinstance(m, bytes) else json.dumps(m).encode() for m in messages]
        server.serve([*lines, b"\n"])
        responses = [json.loads(line) for line in output.getvalue().splitlines()]
        return {response["id"]: response for response in responses}

    def call(self, request_id: int, tool: str, arguments: object, **meta: str) -> dict[str, Any]:
        """Build one tools/call request."""
        params: dict[str, object] = {"name": tool, "arguments": arguments}
        if meta:
            params["_meta"] = meta
        return {"jsonrpc": "2.0", "id": request_id, "method": "tools/call", "params": params}

    def test_handshake(self) -> None:
        """Initialize, ping, and tools/list answer; notifications do not."""
        responses = self.exchange(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-06-18"},
            },
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "ping"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 4, "method": "resources/list"},
            {"jsonrpc": "2.0", "id": 5, "method": "initialize", "params": {"protocolVersion": "1"}},
            b"{not json",
        )
        self.assertEqual(set(responses), {1, 2, 3, 4, 5, None})
        self.assertEqual(responses[1]["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(responses[5]["result"]["protocolVersion"], mcp.PROTOCOL_VERSIONS[0])
        self.assertEqual(responses[2]["result"], {})
        names = [tool["name"] for tool in responses[3]["result"]["tools"]]
        self.assertEqual(names, [tool.name for tool in mcp.TOOLS])
        self.assertEqual(responses[4]["error"]["code"], mcp.METHOD_NOT_FOUND)
        self.assertEqual(responses[None]["error"]["code"], mcp.PARSE_ERROR)
        tools = {tool["name"]: tool for tool in responses[3]["result"]["tools"]}
        self.assertTrue(tools["run"]["annotations"]["openWorldHint"])
        self.assertFalse(tools["exec"]["annotations"]["openWorldHint"])

    def test_invalid_requests(self) -> None:
        """A null id or a non-string method is an invalid request."""
        for message in (
            {"jsonrpc": "2.0", "id": None, "method": "ping"},
            {"jsonrpc": "2.0", "id": 7, "method": 5},
        ):
            with self.subTest(message=message):
                responses = self.exchange(message)
                self.assertEqual(responses[None]["error"]["code"], mcp.INVALID_REQUEST)

    def test_calls(self) -> None:
        """Results carry the --json document; refusals are tool errors."""
        for name, session in (("a", "codex:t1"), ("b", "claude:s1")):
            self.core.backend.add(name, expires=test_core.NOW + 3600, session=session)
            self.core.paths.sandbox(name).mkdir(parents=True)
        responses = self.exchange(
            self.call(1, "list", {"mine": True}, threadId="t1"),
            self.call(2, "info", {"name": "missing"}),
            self.call(3, "nope", {}),
            self.call(4, "destroy", {"name": "a", "mine": True}),
        )
        result = responses[1]["result"]
        self.assertFalse(result["isError"])
        listed = json.loads(result["content"][0]["text"])
        self.assertEqual([entry["name"] for entry in listed], ["a"])
        self.assertIn("codex:t1", self.sessions)
        refused = responses[2]["result"]
        self.assertTrue(refused["isError"])
        self.assertEqual(json.loads(refused["content"][0]["text"])["error"]["code"], "not-found")
        self.assertEqual(responses[3]["error"]["code"], mcp.INVALID_PARAMS)
        exclusive = json.loads(responses[4]["result"]["content"][0]["text"])
        self.assertEqual(exclusive["error"]["code"], "usage")
        self.assertIn("sbx-a", self.core.backend.domains_by_name)


class Stub:
    """Sandboxes whose destroy releases a blocked run."""

    def __init__(self) -> None:
        """Start with nothing created or destroyed."""
        self.existing: set[str] = set()
        self.destroyed: list[str] = []
        self.names: list[str | None] = []
        self.running = threading.Event()
        self.released = threading.Event()

    def create(self, name: str) -> dict[str, object]:
        """Refuse a taken name, after a delay that keeps the call in flight."""
        if name in self.existing:
            time.sleep(1)
            msg = f"a sandbox named '{name}' exists"
            raise SbxError(msg, code="exists")
        return {"name": name}

    def destroy(self, name: str) -> list[str]:
        """Record the name and let the run fail as its sandbox vanished."""
        self.destroyed.append(name)
        self.released.set()
        return [name]

    def dispatch(self, sandboxes: Any, args: argparse.Namespace, *, as_json: bool) -> None:  # noqa: ANN401
        """Create through the server's sandboxes, then block like a run in progress."""
        if not as_json:
            raise AssertionError
        self.names.append(args.name)
        sandboxes.create(args.name)
        self.running.set()
        self.released.wait(5)
        msg = "no sandbox"
        raise SbxError(msg, code="not-found")


class CancelTest(unittest.TestCase):
    """Cancelled and interrupted runs leave no sandbox of theirs behind."""

    def setUp(self) -> None:
        """Route every sandbox and dispatch to the stub."""
        self.stub = Stub()
        self.output = io.BytesIO()
        self.server = mcp.Server(lambda _session: cast("Any", self.stub), self.output, "0.0.0")
        patch = mock.patch.object(mcp, "dispatch", self.stub.dispatch)
        patch.start()
        self.addCleanup(patch.stop)

    def run_call(self, request_id: int, **arguments: object) -> bytes:
        """Encode a run of id in the nixos base."""
        params = {"name": "run", "arguments": {"base": "nixos", "command": ["id"], **arguments}}
        message = {"jsonrpc": "2.0", "id": request_id, "method": "tools/call", "params": params}
        return json.dumps(message).encode()

    @staticmethod
    def cancel(request_id: int) -> bytes:
        """Encode a cancellation of one request."""
        params = {"requestId": request_id}
        message = {"jsonrpc": "2.0", "method": "notifications/cancelled", "params": params}
        return json.dumps(message).encode()

    def test_cancelled_run(self) -> None:
        """A cancellation destroys the run's generated sandbox and suppresses the response."""
        self.server.serve([self.run_call(1), self.cancel(1)])
        self.assertEqual(len(self.stub.destroyed), 1)
        self.assertTrue(self.stub.destroyed[0].startswith("nixos-"))
        self.assertEqual(self.stub.names, self.stub.destroyed)
        self.assertEqual(self.output.getvalue(), b"")

    def test_existing_name_survives(self) -> None:
        """A cancelled run named after another sandbox never destroys it."""
        self.stub.existing.add("x")
        self.server.serve([self.run_call(3, name="x"), self.cancel(3)])
        self.assertEqual(self.stub.destroyed, [])
        self.server.reap_all()
        self.assertEqual(self.stub.destroyed, [])

    def test_terminate(self) -> None:
        """reap_all, the SIGTERM path, destroys every run in progress."""
        self.server.receive(self.run_call(2, name="r1"))
        self.assertTrue(self.stub.running.wait(5))
        self.server.reap_all()
        self.server.serve([])
        self.assertEqual(self.stub.destroyed, ["r1"])
        response = json.loads(self.output.getvalue())
        self.assertEqual(response["id"], 2)
        self.assertTrue(response["result"]["isError"])
