# Copyright (c) 2026 Bad3r
"""The MCP front end of sbx against the fake backend of the core tests."""

import base64
import io
import json
import os
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import TYPE_CHECKING, Any, cast
from unittest import mock

from PIL import Image
from sbx import gui, mcp, ops
from sbx.config import caller_session
from sbx.errors import SbxError
from sbx.results import Document

from . import test_core, test_shares

if TYPE_CHECKING:
    from collections.abc import Callable

    from sbx.model import Meta
    from sbx.sandboxes import Sandboxes

SAMPLES: dict[str, object] = {
    "base": "nixos",
    "flavour": "nixos",
    "name": "probe",
    "net": "none",
    "mem": "2G",
    "cpus": 2,
    "ttl": "30m",
    "wait": "10m",
    "in": ["/work/a", "/work/b"],
    "out": ["/root/report.txt"],
    "to": "/work",
    "timeout": "5m",
    "cwd": "/srv",
    "encoding": "base64",
    "env": {"A": "1", "B": "x y"},
    "user": "sbx",
    "stdin": "text",
    "stdin_base64": "AAE=",
    "command": ["sh", "-c", "true"],
    "source": "probe:/root/x",
    "destination": "/work",
    "mine": True,
    "expired": True,
    "ocr": True,
    "dry_run": True,
    "gui": True,
    "keys": ["ctrl+alt+t", "enter"],
    "text": "-x",
    "mode": "keys",
    "x": 10,
    "y": 20,
    "click": "left",
    "double": True,
    "title": "xterm",
    "class": "XTerm",
    "id": 4194,
    "share": "shared",
}
SNAPSHOT = Path(__file__).with_name("mcp-tools.json")


def samples(tool: ops.Operation) -> dict[str, object]:
    """Return a valid value for every argument of a tool, one of each exclusive set."""
    names = [param.name for param in tool.params if param.mcp]
    names = [name for name in names if name not in tool.one_of[1:]]
    return {name: SAMPLES[name] for name in names}


class ArgumentsTest(unittest.TestCase):
    """Tool arguments reach handlers checked and decoded, never as a command line."""

    def test_every_tool_accepts_its_arguments(self) -> None:
        """Each tool with every argument set decodes, and its schema is closed."""
        for tool in mcp.TOOLS:
            with self.subTest(tool=tool.name):
                args = mcp.parse_arguments(tool, samples(tool))
                self.assertIs(args.operation, tool)
                schema = cast("dict[str, Any]", mcp.definition(tool)["inputSchema"])
                self.assertFalse(schema["additionalProperties"])
                self.assertLessEqual(set(schema["required"]), set(schema["properties"]))

    def test_snapshot(self) -> None:
        """tools/list changes only on purpose; regenerate the file when it does."""
        self.assertEqual(
            [mcp.definition(tool) for tool in mcp.TOOLS], json.loads(SNAPSHOT.read_text())
        )

    def test_decoding(self) -> None:
        """Values keep a leading dash, env becomes NAME=VALUE pairs, and base64 becomes bytes."""
        args = mcp.parse_arguments(
            mcp.TOOLS_BY_NAME["exec"],
            {
                "name": "-x",
                "env": {"A": "1", "B": "x=y"},
                "stdin_base64": "AP8=",
                "command": ["sh", "-c", "x -- y"],
            },
        )
        self.assertEqual(args.text("name"), "-x")
        self.assertEqual(args.strings("env"), ["A=1", "B=x=y"])
        self.assertEqual(args.data("stdin_base64"), b"\x00\xff")
        self.assertEqual(args.strings("command"), ["sh", "-c", "x -- y"])
        self.assertEqual((args.text("encoding"), args.optional("timeout")), ("text", None))
        typed = mcp.parse_arguments(mcp.TOOLS_BY_NAME["type"], {"name": "g", "text": "--help"})
        self.assertEqual(typed.text("text"), "--help")
        listed = mcp.parse_arguments(mcp.TOOLS_BY_NAME["list"], {"mine": None})
        self.assertFalse(listed.flag("mine"))

    def test_refusals(self) -> None:
        """Malformed arguments are usage errors."""
        cases: list[tuple[str, object]] = [
            ("destroy", {"name": "a", "mine": True}),
            ("destroy", {"mine": False}),
            ("info", {"name": "a", "verbose": True}),
            ("info", {}),
            ("info", ["a"]),
            ("create", {"base": "nixos", "cpus": True}),
            ("create", {"base": "nixos", "cpus": "2"}),
            ("create", {"base": "nixos", "net": "lan"}),
            ("exec", {"name": "a", "command": "id"}),
            ("exec", {"name": "a", "command": []}),
            ("exec", {"name": "a", "env": {"A": 1}, "command": ["env"]}),
            ("exec", {"name": "a", "stdin_base64": "%%", "command": ["cat"]}),
            ("exec", {"name": "a", "stdin": 1, "command": ["cat"]}),
            ("list", {"mine": "yes"}),
            ("key", {"name": "g", "keys": "a"}),
            ("key", {"name": "g", "keys": []}),
            ("type", {"name": "g", "text": ["a"]}),
            ("share_attach", {"name": "g"}),
            ("mouse", {"name": "g", "x": 1}),
            ("mouse", {"name": "g", "x": 1, "y": "2"}),
            ("mouse", {"name": "g", "x": 1, "y": 2, "click": "back"}),
            ("window_wait", {"name": "g"}),
            ("window_wait", {"name": "g", "title": "a", "class": "b"}),
            ("window_focus", {"name": "g"}),
            ("window_focus", {"name": "g", "id": "1"}),
        ]
        for tool, arguments in cases:
            with self.subTest(tool=tool, arguments=arguments):
                with self.assertRaises(SbxError) as raised:
                    mcp.parse_arguments(mcp.TOOLS_BY_NAME[tool], arguments)
                self.assertEqual(raised.exception.code, "usage")

    def test_session(self) -> None:
        """Codex names its session per call, preferred to the thread; else the environment."""
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "s1"}):
            meta = {"sessionId": "root", "threadId": "child"}
            self.assertEqual(mcp.session_of(meta), "codex:root")
            self.assertEqual(mcp.session_of({"threadId": "t1"}), "codex:t1")
            self.assertEqual(mcp.session_of({"sessionId": "", "threadId": ""}), "claude:s1")
            self.assertEqual(mcp.session_of(None), "claude:s1")
        environment = {"CODEX_SESSION_ID": "root", "CODEX_THREAD_ID": "child"}
        with mock.patch.dict(os.environ, environment, clear=True):
            self.assertEqual(caller_session(), "codex:root")


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
        self.assertEqual(cast("Meta", domains["sbx-r"].meta).token, replacement.token)
        self.assertTrue(self.core.paths.sandbox("r").is_dir())
        self.assertEqual(output.getvalue(), b"")

    def test_end_of_input_ends_a_wait(self) -> None:
        """A create waiting for capacity when the client closes stdin fails and drops its ticket."""
        for index in range(3):
            self.core.backend.add(f"r{index}", expires=test_core.NOW + 60)
        output = io.BytesIO()
        server = mcp.Server(self.core.sandboxes, output, "0.0.0")
        call = self.call(1, "create", {"base": "nixos", "name": "w", "wait": "10m"})
        server.receive(json.dumps(call).encode())
        queue = self.core.paths.queue
        deadline = time.monotonic() + 5
        while not (queue.is_dir() and any(queue.iterdir())) and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(any(queue.iterdir()))
        server.serve([])
        self.assertLess(time.monotonic(), deadline + 5)
        response = json.loads(output.getvalue())
        refused = json.loads(response["result"]["content"][0]["text"])
        self.assertEqual(refused["error"]["code"], "cancelled")
        self.assertEqual(list(queue.iterdir()), [])

    def test_calls(self) -> None:
        """Results carry the --json document; refusals are tool errors."""
        for name, session in (("a", "codex:t1"), ("b", "claude:s1")):
            self.core.backend.add(name, expires=test_core.NOW + 3600, session=session)
            self.core.paths.sandbox(name).mkdir(parents=True)
        responses = self.exchange(
            self.call(1, "list", {"mine": True}, sessionId="t1", threadId="child"),
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
        # Cloud bases reach the sandboxes, which also get the GUI flag.
        codes = [
            json.loads(responses[n]["result"]["content"][0]["text"])["error"]["code"]
            for n in (5, 6)
        ]
        self.assertEqual(codes, ["base-missing", "unknown-base"])

    def test_failed_run(self) -> None:
        """A run whose export fails is a tool error that keeps the command's result.

        The run's sandbox carries the call's token, passed without replacing create.
        """
        opened: list[Sandboxes] = []

        def open_sandboxes(session: str | None) -> Any:  # noqa: ANN401
            opened.append(self.core.sandboxes(session))
            return opened[-1]

        output = io.BytesIO()
        server = mcp.Server(open_sandboxes, output, "0.0.0")
        arguments = {
            "base": "nixos",
            "name": "r",
            "out": ["/root/missing.json"],
            "to": str(self.core.scratch / "tmp"),
            "command": ["true"],
        }

        def token_hex(_size: int) -> str:
            return "feedfacecafebeef"

        tokens = SimpleNamespace(token_hex=token_hex)
        with mock.patch.object(mcp, "secrets", tokens):
            server.receive(json.dumps(self.call(1, "run", arguments)).encode())
        # The end of input would cancel the create, so it waits for the response.
        deadline = time.monotonic() + 10
        while not output.getvalue() and time.monotonic() < deadline:
            time.sleep(0.05)
        server.serve([])
        result = json.loads(output.getvalue())["result"]
        self.assertTrue(result["isError"])
        error = json.loads(result["content"][0]["text"])["error"]
        self.assertEqual((error["code"], error["phase"]), ("run-incomplete", "out"))
        self.assertEqual(error["run"]["exec"]["exit_code"], 0)
        self.assertEqual(error["run"]["sandbox"]["token"], "feedfacecafebeef")
        self.assertEqual(error["run"]["cleanup"]["destroyed"], ["r"])
        self.assertNotIn("create", vars(opened[0]))

    def test_screenshot_image_and_optional_ocr(self) -> None:
        """PNG and PPM captures include a viewable image, with OCR only when requested."""
        for image_format, mime in (("PNG", "image/png"), ("PPM", "image/x-portable-pixmap")):
            for ocr in (None, False, True):
                with self.subTest(image_format=image_format, ocr=ocr):
                    self.core.backend.add("screen", expires=test_core.NOW + 3600)
                    self.core.paths.sandbox("screen").joinpath("xfer").mkdir(
                        parents=True, exist_ok=True
                    )

                    def screenshot(
                        _domain: str,
                        target: Path,
                        *,
                        source_format: str = image_format,
                        source_mime: str = mime,
                    ) -> str:
                        Image.new("RGB", (3, 2), (20, 40, 60)).save(target, format=source_format)
                        return source_mime

                    arguments: dict[str, object] = {"name": "screen"}
                    if ocr is not None:
                        arguments["ocr"] = ocr
                    with (
                        mock.patch.object(self.core.backend, "screenshot", screenshot),
                        mock.patch.object(gui, "run", return_value="screen text\n") as read,
                    ):
                        result = self.exchange(self.call(1, "screenshot", arguments))[1]["result"]
                    self.assertFalse(result["isError"])
                    text, image = result["content"]
                    self.assertEqual(text["type"], "text")
                    document = json.loads(text["text"])
                    self.assertEqual(document["mime"], mime)
                    saved = self.core.paths.sandbox("screen") / "xfer"
                    self.assertEqual(saved, Path(document["path"]).parent)
                    self.assertTrue(Path(document["path"]).is_file())
                    self.assertEqual((image["type"], image["mimeType"]), ("image", "image/png"))
                    data = base64.b64decode(image["data"], validate=True)
                    with Image.open(io.BytesIO(data)) as decoded:
                        self.assertEqual((decoded.format, decoded.size), ("PNG", (3, 2)))
                        self.assertEqual(decoded.getpixel((1, 1)), (20, 40, 60))
                    if ocr:
                        self.assertEqual(document["text"], "screen text\n")
                        read.assert_called_once_with(
                            [self.core.settings.tools.tesseract, document["path"], "stdout"]
                        )
                    else:
                        self.assertNotIn("text", document)
                        read.assert_not_called()

    def documents(self, *calls: dict[str, Any]) -> list[tuple[bool, dict[str, Any]]]:
        """Send calls one at a time; return each result's error flag and document."""
        results: list[tuple[bool, dict[str, Any]]] = []
        for call in calls:
            result = self.exchange(call)[call["id"]]["result"]
            results.append((result["isError"], json.loads(result["content"][0]["text"])))
        return results

    def test_gui_input(self) -> None:
        """Keys and text reach a GUI display; text may start with a dash, keys must be a list."""
        self.core.sandboxes().create(self.core.request(gui=True))
        with mock.patch.object(gui.time, "sleep"):
            pressed, typed, refused = self.documents(
                self.call(1, "key", {"name": "t1", "keys": ["ctrl+alt+t", "enter"]}),
                self.call(2, "type", {"name": "t1", "text": "-x\n"}),
                self.call(3, "key", {"name": "t1", "keys": "a"}),
            )
        self.assertEqual(pressed, (False, {"sandbox": "t1", "keys": ["ctrl+alt+t", "enter"]}))
        self.assertEqual(typed, (False, {"sandbox": "t1", "characters": 3}))
        self.assertEqual((refused[0], refused[1]["error"]["code"]), (True, "usage"))
        self.assertEqual([codes for _domain, codes in self.core.backend.keys], [[29, 56, 20], [28]])
        self.assertEqual(self.core.backend.execs[-1][1], b"-x\n")

    def test_gui_control_refusals(self) -> None:
        """Negative coordinates and a missing pattern are tool errors before the guest runs."""
        self.core.sandboxes().create(self.core.request(gui=True))
        negative, missing, plain = self.documents(
            self.call(1, "mouse", {"name": "t1", "x": -1, "y": 5}),
            self.call(2, "window_wait", {"name": "t1", "timeout": "5s"}),
            self.call(3, "window_list", {"name": "t1", "title": "x"}),
        )
        self.assertEqual((negative[0], negative[1]["error"]["code"]), (True, "invalid-argument"))
        self.assertEqual((missing[0], missing[1]["error"]["code"]), (True, "usage"))
        self.assertEqual((plain[0], plain[1]["error"]["code"]), (True, "usage"))
        self.assertEqual(self.core.backend.execs, [])

    def test_shares(self) -> None:
        """share_attach and share_detach return the share's JSON form."""
        backend = test_shares.ShareFake()
        backend.linger = 0
        self.core.backend = backend
        backend.add("s", expires=test_core.NOW + 3600)
        self.core.paths.sandbox("s").mkdir(parents=True)
        arguments = {"name": "s", "share": "shared"}
        attached, detached, missing = self.documents(
            self.call(1, "share_attach", arguments),
            self.call(2, "share_detach", arguments),
            self.call(3, "share_detach", arguments),
        )
        host_path = str(self.core.paths.sandbox("s").resolve() / "shared")
        share = {"sandbox": "s", "tag": "shared", "read_only": False, "host_path": host_path}
        self.assertEqual(attached, (False, share | {"attached": True}))
        self.assertEqual(detached, (False, share | {"attached": False}))
        self.assertEqual((missing[0], missing[1]["error"]["code"]), (True, "not-attached"))

    def test_stdin_conflict(self) -> None:
        """Text and base64 stdin together are refused before the command runs."""
        self.core.backend.add("a", expires=test_core.NOW + 3600)
        arguments = {"name": "a", "stdin": "x", "stdin_base64": "eA==", "command": ["cat"]}
        ((failed, document),) = self.documents(self.call(1, "exec", arguments))
        self.assertEqual((failed, document["error"]["code"]), (True, "usage"))
        self.assertEqual(self.core.backend.execs, [])

    def test_screenshot_failure(self) -> None:
        """A failed capture returns a tool error without an image block."""
        result = self.exchange(self.call(1, "screenshot", {"name": "missing"}))[1]["result"]
        self.assertTrue(result["isError"])
        (text,) = result["content"]
        self.assertEqual(json.loads(text["text"])["error"]["code"], "not-found")


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

    def invoke(
        self,
        _operation: ops.Operation,
        open_sandboxes: Callable[[str | None], Any],
        args: ops.Args,
        ctx: ops.Ctx,
    ) -> object:
        """Run like the run handler: create with the call's token, then destroy by name."""
        if ctx.stdio_attached:
            raise AssertionError
        name = args.optional("name") or "nixos-gen"
        try:
            sandboxes = open_sandboxes(ctx.session)
            sandboxes.create(name, token=ctx.token)
            sandboxes.destroy(name)
        except SbxError as error:
            return ops.fail(error)
        return Document({"name": name})


class CancelTest(unittest.TestCase):
    """Cancelled and interrupted runs remove their own sandbox and nothing else."""

    def setUp(self) -> None:
        """Route every sandbox and call to the stub."""
        self.stub = Stub()
        self.output = io.BytesIO()
        self.server = mcp.Server(lambda _session: cast("Any", self.stub), self.output, "0.0.0")
        patch = mock.patch.object(mcp.ops, "invoke", self.stub.invoke)
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
