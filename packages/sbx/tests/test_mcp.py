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
from sbx.core import Meta, SbxError

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
    "gui": True,
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
        argv, _ = mcp.TOOLS_BY_NAME["create"].command_line({"base": "debian-13", "gui": True})
        self.assertEqual(argv, ["create", "--gui", "debian-13"])
        args = build_parser().parse_args(argv)
        self.assertEqual((args.base, args.gui), ("debian-13", True))
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

    def test_cancel_during_boot_spares_a_namesake(self) -> None:
        """A run cancelled while booting leaves a sandbox later created under its name."""
        gate = threading.Event()
        pings: list[str] = []
        ping = self.core.backend.agent

        def agent(domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:
            pings.append(domain)
            if len(pings) == 1:
                gate.wait(5)
                msg = "guest agent unreachable"
                raise SbxError(msg, code="agent")
            return ping(domain, command, timeout)

        output = io.BytesIO()
        server = mcp.Server(self.core.sandboxes, output, "0.0.0")
        domains = self.core.backend.domains_by_name
        with mock.patch.object(self.core.backend, "agent", agent):
            server.receive(
                json.dumps(
                    self.call(1, "run", {"base": "nixos", "name": "r", "command": ["true"]})
                ).encode()
            )
            deadline = time.monotonic() + 5
            while not pings and time.monotonic() < deadline:
                time.sleep(0.05)
            cancel = {
                "jsonrpc": "2.0",
                "method": "notifications/cancelled",
                "params": {"requestId": 1},
            }
            server.receive(json.dumps(cancel).encode())
            while "sbx-r" in domains and time.monotonic() < deadline:
                time.sleep(0.05)
            replacement = self.core.sandboxes("claude:two").create(self.core.request(name="r"))
            gate.set()
            server.serve([])
        self.assertEqual(cast("Meta", domains["sbx-r"].meta).token, replacement["token"])
        self.assertTrue(self.core.paths.sandbox("r").is_dir())
        self.assertEqual(output.getvalue(), b"")

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
            self.call(5, "create", {"base": "debian-13"}),
            self.call(6, "create", {"base": "debian-13", "gui": True}),
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
        # Cloud bases reach core, which also gets the GUI flag.
        codes = [
            json.loads(responses[n]["result"]["content"][0]["text"])["error"]["code"]
            for n in (5, 6)
        ]
        self.assertEqual(codes, ["base-missing", "unknown-base"])


class Stub:
    """Sandboxes held as name to creation token; create blocks like a boot until released."""

    def __init__(self) -> None:
        """Start with no domains."""
        self.domains: dict[str, str | None] = {}
        self.tokens: list[str | None] = []
        self.destroyed: list[str] = []
        self.defined = threading.Event()
        self.released = threading.Event()

    def create(self, name: str, *, token: str | None = None) -> dict[str, object]:
        """Refuse a taken name after a delay, or define the domain and boot until released."""
        if name in self.domains:
            time.sleep(1)
            msg = f"a sandbox named '{name}' exists"
            raise SbxError(msg, code="exists")
        self.domains[name] = token
        self.tokens.append(token)
        self.defined.set()
        self.released.wait(5)
        return {"name": name}

    def destroy(self, name: str) -> list[str]:
        """Remove one domain by name, as a run's own cleanup does."""
        if self.domains.pop(name, "missing") == "missing":
            msg = f"no sandbox named '{name}'"
            raise SbxError(msg, code="not-found")
        self.destroyed.append(name)
        return [name]

    def destroy_created(self, token: str) -> list[str]:
        """Remove the domains carrying `token` and end a boot in progress."""
        names = [name for name, carried in self.domains.items() if carried == token]
        for name in names:
            del self.domains[name]
        self.destroyed.extend(names)
        if names:
            self.released.set()
        return names

    def dispatch(self, sandboxes: Any, args: argparse.Namespace, *, as_json: bool) -> object:  # noqa: ANN401
        """Run like cli._run: create, then destroy by name."""
        if not as_json:
            raise AssertionError
        name = args.name or "nixos-gen"
        sandboxes.create(name)
        sandboxes.destroy(name)
        return {"name": name}, 0


class CancelTest(unittest.TestCase):
    """Cancelled and interrupted runs remove their own sandbox and nothing else."""

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
        """A cancellation destroys the booting sandbox and suppresses the response."""
        self.server.serve([self.run_call(1), self.cancel(1)])
        self.assertEqual(self.stub.destroyed, ["nixos-gen"])
        self.assertEqual(self.stub.domains, {})
        self.assertEqual(self.output.getvalue(), b"")

    def test_existing_name_survives(self) -> None:
        """A cancelled run named after another sandbox never destroys it."""
        self.stub.domains["x"] = "other"
        self.server.serve([self.run_call(3, name="x"), self.cancel(3)])
        self.server.reap_all()
        self.assertEqual((self.stub.domains, self.stub.destroyed), ({"x": "other"}, []))

    def test_terminate_during_boot(self) -> None:
        """reap_all, the SIGTERM path, destroys a run's sandbox while it still boots."""
        self.server.receive(self.run_call(2))
        self.assertTrue(self.stub.defined.wait(5))
        self.server.reap_all()
        self.server.serve([])
        self.assertEqual(self.stub.destroyed, ["nixos-gen"])
        response = json.loads(self.output.getvalue())
        self.assertEqual(response["id"], 2)
        self.assertTrue(response["result"]["isError"])

    def test_replacement_survives(self) -> None:
        """A stale reaper never destroys a later sandbox of the same name."""
        self.stub.released.set()
        self.server.serve([self.run_call(4, name="r")])
        self.assertEqual(self.stub.destroyed, ["r"])
        (token,) = self.stub.tokens
        self.stub.domains["r"] = "replacement"
        gate = threading.Event()
        alive = threading.Thread(target=gate.wait)
        alive.start()
        reaper = threading.Thread(target=self.server.reap, args=(mcp.Call(alive, None, token),))
        reaper.start()
        time.sleep(0.7)
        gate.set()
        reaper.join(5)
        alive.join(5)
        self.assertIsNotNone(token)
        self.assertEqual(self.stub.domains, {"r": "replacement"})
        self.assertEqual(self.stub.destroyed, ["r"])
