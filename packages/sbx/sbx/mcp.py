# Copyright (c) 2026 Bad3r
"""MCP stdio front end of sbx.

Each tool turns its arguments into the command line of one verb and runs it
through the CLI's parser and dispatch in JSON mode, so a tool accepts what its
verb accepts and returns the document `sbx <verb> --json` prints.
"""

import dataclasses
import functools
import json
import os
import secrets
import signal
import sys
import threading
import time
import traceback
from dataclasses import dataclass
from typing import TYPE_CHECKING, BinaryIO, cast

from sbx import journal
from sbx.cli import build_parser, dispatch
from sbx.core import (
    FLAVOURS,
    NETS,
    Backend,
    Paths,
    Sandboxes,
    SbxError,
    Settings,
    caller_session,
)

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable
    from pathlib import Path

# 2025-03-26 is left out: it requires JSON-RPC batches, which this server rejects.
PROTOCOL_VERSIONS = ("2025-11-25", "2025-06-18", "2024-11-05")
PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603
COMMAND = "command"
INSTRUCTIONS = (
    "Disposable VMs for unknown binaries, downloads, and untrusted repositories; "
    "the sbx skill says when to use them. Host paths sit under the git checkout of "
    "the directory the client started in, ~/trees, or $TMPDIR; relative paths "
    "resolve against that directory, so pass absolute ones."
)
# Clients cut long tool results, so a lower cap keeps `truncated` truthful.
OUTPUT_LIMIT = 64 * 1024

type Json = dict[str, object]


@dataclass(frozen=True)
class Param:
    """One tool argument and the command-line form it takes."""

    name: str
    schema: Json
    # None makes the argument positional.
    flag: str | None = None
    required: bool = False


@dataclass(frozen=True)
class Tool:
    """One MCP tool over one sbx verb."""

    name: str
    verb: tuple[str, ...]
    title: str
    description: str
    params: tuple[Param, ...] = ()
    read_only: bool = False
    destructive: bool = False
    open_world: bool = False

    def definition(self) -> Json:
        """Return the tools/list entry."""
        properties = {param.name: param.schema for param in self.params}
        required = [param.name for param in self.params if param.required]
        return {
            "name": self.name,
            "title": self.title,
            "description": self.description,
            "inputSchema": {
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": False,
            },
            "annotations": {
                "title": self.title,
                "readOnlyHint": self.read_only,
                "destructiveHint": self.destructive,
                "openWorldHint": self.open_world,
            },
        }

    def command_line(self, arguments: object) -> tuple[list[str], list[str]]:
        """Return the verb's arguments and the guest command."""
        if arguments is None:
            arguments = {}
        if not isinstance(arguments, dict):
            msg = "arguments must be an object"
            raise SbxError(msg, code="usage")
        given = cast("dict[str, object]", arguments)
        unknown = sorted(set(given) - {param.name for param in self.params})
        if unknown:
            msg = f"{self.name}: unknown arguments: {', '.join(unknown)}"
            raise SbxError(msg, code="usage")
        options: list[str] = []
        positionals: list[str] = []
        command: list[str] = []
        for param in self.params:
            value = given.get(param.name)
            if value is None:
                if param.required:
                    msg = f"{self.name}: '{param.name}' is required"
                    raise SbxError(msg, code="usage")
                continue
            if param.name == COMMAND:
                command = _strings(self.name, param, value)
                if not command:
                    msg = f"{self.name}: '{COMMAND}' needs at least one word"
                    raise SbxError(msg, code="usage")
            elif param.flag is None:
                positionals.append(_positional(self.name, param, value))
            else:
                options.extend(_options(self.name, param, value))
        return [*self.verb, *options, *positionals], command


def _strings(tool: str, param: Param, value: object) -> list[str]:
    if not isinstance(value, list):
        msg = f"{tool}: '{param.name}' must be a list of strings"
        raise SbxError(msg, code="usage")
    items = cast("list[object]", value)
    if not all(isinstance(item, str) for item in items):
        msg = f"{tool}: '{param.name}' must be a list of strings"
        raise SbxError(msg, code="usage")
    return cast("list[str]", items)


def _positional(tool: str, param: Param, value: object) -> str:
    if not isinstance(value, str):
        msg = f"{tool}: '{param.name}' must be a string"
        raise SbxError(msg, code="usage")
    # A leading dash would parse as an option, such as --mine in place of a name.
    if value.startswith("-"):
        msg = f"{tool}: '{param.name}' must not start with '-'"
        raise SbxError(msg, code="usage")
    return value


def _options(tool: str, param: Param, value: object) -> list[str]:
    match param.schema["type"]:
        case "boolean":
            if not isinstance(value, bool):
                msg = f"{tool}: '{param.name}' must be a boolean"
                raise SbxError(msg, code="usage")
            return [f"{param.flag}"] if value else []
        case "integer":
            if isinstance(value, bool) or not isinstance(value, int):
                msg = f"{tool}: '{param.name}' must be an integer"
                raise SbxError(msg, code="usage")
            return [f"{param.flag}={value}"]
        case "array":
            return [f"{param.flag}={item}" for item in _strings(tool, param, value)]
        case _:
            if not isinstance(value, str):
                msg = f"{tool}: '{param.name}' must be a string"
                raise SbxError(msg, code="usage")
            # The = form keeps a value that starts with a dash a value.
            return [f"{param.flag}={value}"]


def _string(description: str, **extra: object) -> Json:
    return {"type": "string", "description": description, **extra}


def _boolean(description: str) -> Json:
    return {"type": "boolean", "description": description}


def _list(description: str, **extra: object) -> Json:
    return {"type": "array", "items": {"type": "string"}, "description": description, **extra}


NAME = Param("name", _string("sandbox name"), required=True)
TIMEOUT = Param("timeout", _string("command timeout such as 10m"), flag="--timeout")
GUEST_COMMAND = Param(
    COMMAND,
    _list("argv of the guest command, run without a shell; wrap pipes in sh -c", minItems=1),
    required=True,
)
CREATE_PARAMS = (
    # Windows bases come from the settings, so the schema names no fixed set.
    Param(
        "base",
        _string(f"base to boot: {', '.join(FLAVOURS)}, or a Windows base that base_list reports"),
        required=True,
    ),
    Param("name", _string("sandbox name; default <base>-<6 hex>"), flag="--name"),
    Param("net", _string("network; default none", enum=list(NETS)), flag="--net"),
    Param("mem", _string("memory such as 2G"), flag="--mem"),
    Param("cpus", {"type": "integer", "minimum": 1, "description": "vCPUs"}, flag="--cpus"),
    Param("ttl", _string("lifetime such as 30m or 2h"), flag="--ttl"),
)

TOOLS = (
    Tool(
        "create",
        ("create",),
        "Create a sandbox",
        "Start a sandbox and wait until SSH answers; returns its name, CID, and TTL.",
        CREATE_PARAMS,
        open_world=True,
    ),
    Tool(
        "run",
        ("run",),
        "Run a command in a one-shot sandbox",
        "Create a sandbox, copy inputs to /root/ (C:\\sbx\\ on Windows), run the command, "
        "copy outputs out, and destroy the sandbox even when a step fails; returns "
        "{sandbox, in, exec, out}.",
        (
            *CREATE_PARAMS,
            Param("in", _list("host paths copied into /root/ or C:\\sbx\\"), flag="--in"),
            Param("out", _list("guest paths copied to 'to' afterwards"), flag="--out"),
            Param("to", _string("host directory for 'out'"), flag="--to"),
            TIMEOUT,
            GUEST_COMMAND,
        ),
        open_world=True,
    ),
    Tool(
        "exec",
        ("exec",),
        "Run a command in a sandbox",
        "Run a command over SSH, or through qemu-ga on Windows; returns "
        "{exit_code, stdout, stderr, truncated, timed_out}. "
        "A failing guest command is no tool error: its status is exit_code, 124 after timeout.",
        (
            NAME,
            TIMEOUT,
            Param("agent", _boolean("run through qemu-ga instead of SSH"), flag="--agent"),
            GUEST_COMMAND,
        ),
    ),
    Tool(
        "cp",
        ("cp",),
        "Copy between host and sandbox",
        "Copy a file or directory; one side is <name>:<path>. Without a destination a copy "
        "out lands in the sandbox's xfer directory; copies out never overwrite.",
        (
            Param("source", _string("host path or <name>:<path>"), required=True),
            Param("destination", _string("<name>:<path> or a host path")),
        ),
    ),
    Tool(
        "destroy",
        ("destroy",),
        "Destroy sandboxes",
        "Stop and delete one sandbox, every sandbox of this agent session, or every expired "
        "one; give exactly one of name, mine, and expired. Returns the destroyed names.",
        (
            Param("name", _string("sandbox name")),
            Param("mine", _boolean("sandboxes of this agent session"), flag="--mine"),
            Param("expired", _boolean("sandboxes past their TTL"), flag="--expired"),
        ),
        destructive=True,
    ),
    Tool(
        "list",
        ("list",),
        "List sandboxes",
        "Describe every sandbox: state, base, CID, TTL left, session, and xfer directory.",
        (Param("mine", _boolean("only sandboxes of this agent session"), flag="--mine"),),
        read_only=True,
    ),
    Tool(
        "info",
        ("info",),
        "Describe a sandbox",
        "Describe one sandbox as list does.",
        (NAME,),
        read_only=True,
    ),
    Tool(
        "screenshot",
        ("screenshot",),
        "Capture a sandbox display",
        "Save the display as PNG or PPM in the sandbox's xfer directory and return its path, "
        "with the text tesseract reads under ocr.",
        (NAME, Param("ocr", _boolean("add the text tesseract reads"), flag="--ocr")),
    ),
    Tool(
        "gc",
        ("gc",),
        "Remove expired and orphaned sandboxes",
        "Remove sandboxes past their TTL, shut-off ones, and orphaned domains or directories.",
        (Param("dry_run", _boolean("report without removing"), flag="--dry-run"),),
        destructive=True,
    ),
    Tool(
        "base_list",
        ("base", "list"),
        "List bases",
        "Report each base and whether it is built.",
        read_only=True,
    ),
    Tool(
        "base_build",
        ("base", "build"),
        "Build a base",
        "Build a Nix base offline from the configured flake; create needs it first.",
        (Param("flavour", _string("base to build", enum=list(FLAVOURS)), required=True),),
    ),
)

TOOLS_BY_NAME = {tool.name: tool for tool in TOOLS}


def session_of(meta: object) -> str | None:
    """Return the agent session behind one call."""
    # Codex clears the server's environment but names its thread in each call;
    # Claude Code exports CLAUDE_CODE_SESSION_ID when it starts the server.
    if isinstance(meta, dict):
        thread = cast("dict[str, object]", meta).get("threadId")
        if isinstance(thread, str) and thread:
            return f"codex:{thread}"
    return caller_session()


def _text(document: object, *, error: bool) -> Json:
    text = json.dumps(document, separators=(",", ":"))
    return {"content": [{"type": "text", "text": text}], "isError": error}


def _valid_id(request_id: object) -> bool:
    return isinstance(request_id, str) or (
        isinstance(request_id, int) and not isinstance(request_id, bool)
    )


@dataclass
class Call:
    """A tools/call in progress."""

    thread: threading.Thread
    session: str | None
    # A run's creation token, which its sandbox's metadata carries from define on.
    token: str | None = None
    cancelled: bool = False


class Server:
    """JSON-RPC over newline-delimited stdio; each tool call runs on its own thread."""

    def __init__(
        self, open_sandboxes: Callable[[str | None], Sandboxes], output: BinaryIO, version: str
    ) -> None:
        """Bind the sandbox factory and the protocol's output stream."""
        self._open = open_sandboxes
        self._output = output
        self._version = version
        self._lock = threading.Lock()
        self._calls: dict[object, Call] = {}
        self._threads: list[threading.Thread] = []

    def send(self, message: Json) -> None:
        """Write one message as a single line."""
        data = json.dumps(message, separators=(",", ":")).encode() + b"\n"
        with self._lock:
            self._output.write(data)
            self._output.flush()

    def _reply(self, request_id: object, result: Json) -> None:
        self.send({"jsonrpc": "2.0", "id": request_id, "result": result})

    def _fail(self, request_id: object, code: int, message: str) -> None:
        self.send({"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}})

    def receive(self, line: bytes) -> None:
        """Handle one line of input."""
        try:
            message: object = json.loads(line)
        except ValueError as error:
            self._fail(None, PARSE_ERROR, f"invalid JSON: {error}")
            return
        if not isinstance(message, dict):
            self._fail(None, INVALID_REQUEST, "expected a JSON-RPC object")
            return
        self.handle(cast("Json", message))

    def handle(self, message: Json) -> None:
        """Answer a request or act on a notification; responses need nothing."""
        method = message.get("method")
        params: object = message.get("params") or {}
        if "id" not in message:
            if method == "notifications/cancelled" and isinstance(params, dict):
                self.cancel(cast("Json", params).get("requestId"))
            return
        request_id = message["id"]
        if "method" not in message:
            return
        if not _valid_id(request_id) or not isinstance(method, str):
            self._fail(None, INVALID_REQUEST, "a request needs a string or integer id and a method")
            return
        if not isinstance(params, dict):
            self._fail(request_id, INVALID_PARAMS, "params must be an object")
            return
        params = cast("Json", params)
        match method:
            case "initialize":
                self._reply(request_id, self.initialize(params))
            case "ping":
                self._reply(request_id, {})
            case "tools/list":
                self._reply(request_id, {"tools": [tool.definition() for tool in TOOLS]})
            case "tools/call":
                self.start(request_id, params)
            case _:
                self._fail(request_id, METHOD_NOT_FOUND, f"unknown method: {method}")

    def initialize(self, params: Json) -> Json:
        """Agree on a protocol version and describe the server."""
        requested = params.get("protocolVersion")
        version = requested if requested in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0]
        return {
            "protocolVersion": version,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "sbx", "title": "sbx sandboxes", "version": self._version},
            "instructions": INSTRUCTIONS,
        }

    def start(self, request_id: object, params: Json) -> None:
        """Run one tools/call on its own thread."""
        name = params.get("name")
        tool = TOOLS_BY_NAME.get(name) if isinstance(name, str) else None
        if tool is None:
            self._fail(request_id, INVALID_PARAMS, f"unknown tool: {name}")
            return
        arguments: object = params.get("arguments")
        token = secrets.token_hex(8) if tool.name == "run" else None
        session = session_of(params.get("_meta"))
        thread = threading.Thread(
            target=self._call, args=(request_id, tool, arguments, session), name=f"sbx-{tool.name}"
        )
        with self._lock:
            self._calls[request_id] = Call(thread, session, token)
        self._spawn(thread)

    def _spawn(self, thread: threading.Thread) -> None:
        self._threads = [*filter(threading.Thread.is_alive, self._threads), thread]
        thread.start()

    def call(
        self, tool: Tool, arguments: object, session: str | None, record: Call | None = None
    ) -> Json:
        """Run one tool and return its result; sbx refusals are tool errors."""
        try:
            argv, command = tool.command_line(arguments)
            args = build_parser().parse_args(argv)
            args.command = command
            sandboxes = self._open(session)
            if record is not None and record.token is not None:
                sandboxes.create = functools.partial(sandboxes.create, token=record.token)
            document, _code = dispatch(sandboxes, args, as_json=True)
        except (SbxError, OSError) as error:
            code = error.code if isinstance(error, SbxError) else "os-error"
            journal.record(f"failed: {error}", code=code)
            return _text({"error": {"code": code, "message": str(error)}}, error=True)
        return _text(document, error=False)

    def _call(self, request_id: object, tool: Tool, arguments: object, session: str | None) -> None:
        result: Json | None = None
        failure = ""
        with self._lock:
            record = self._calls.get(request_id)
        try:
            result = self.call(tool, arguments, session, record)
        except Exception as error:  # noqa: BLE001
            traceback.print_exc(file=sys.stderr)
            failure = f"{tool.name}: {error!r}"
        with self._lock:
            call = self._calls.pop(request_id, None)
        # A cancelled request gets no response.
        if call is not None and call.cancelled:
            return
        if result is None:
            self._fail(request_id, INTERNAL_ERROR, failure)
        else:
            self._reply(request_id, result)

    def cancel(self, request_id: object) -> None:
        """Drop the response to a call and destroy the sandbox of a cancelled run."""
        with self._lock:
            call = self._calls.get(request_id)
            if call is None:
                return
            call.cancelled = True
        if call.token is not None:
            reaper = threading.Thread(target=self.reap, args=(call,), name="sbx-cancel")
            self._spawn(reaper)

    def _destroy(self, call: Call) -> bool:
        """Destroy the sandbox carrying the call's token; False while there is none."""
        try:
            return bool(self._open(call.session).destroy_created(str(call.token)))
        except SbxError as error:
            print(
                f"sbx-mcp: cannot destroy the sandbox of a cancelled run: {error}", file=sys.stderr
            )
            return True

    def reap(self, call: Call) -> None:
        """Destroy a cancelled run's sandbox as soon as it exists, until the call ends."""
        # A namesake created later never carries this call's token.
        while call.thread.is_alive():
            if self._destroy(call):
                return
            time.sleep(0.5)

    def reap_all(self) -> None:
        """Destroy the sandbox of every run in progress, booting ones included."""
        # SIGTERM may interrupt the main thread inside a locked section, so no lock here.
        for call in list(self._calls.values()):
            if call.token is not None:
                self._destroy(call)

    def serve(self, lines: Iterable[bytes]) -> None:
        """Handle input until it ends, then wait for running calls."""
        for line in lines:
            if line.strip():
                self.receive(line)
        for thread in self._threads:
            thread.join()


def serve(settings_path: Path, version: str) -> int:
    """Run the server on stdio until the client closes stdin."""
    # Codex starts MCP servers with a cleared environment, and both systemctl
    # --user and qemu:///session find the user's daemons through this variable.
    os.environ.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    try:
        settings = Settings.load(settings_path)
    except SbxError as error:
        print(f"sbx-mcp: {error}", file=sys.stderr)
        return 1
    settings = dataclasses.replace(settings, output_limit=min(settings.output_limit, OUTPUT_LIMIT))
    # Helpers inherit fds 0 and 1, so the protocol moves to private copies.
    protocol_in = os.fdopen(os.dup(0), "rb")
    protocol_out = os.fdopen(os.dup(1), "wb")
    devnull = os.open(os.devnull, os.O_RDONLY)
    os.dup2(devnull, 0)
    os.close(devnull)
    os.dup2(2, 1)

    def open_sandboxes(session: str | None) -> Sandboxes:
        def connect(require_slice: bool) -> Backend:  # noqa: FBT001
            from sbx.backend import LibvirtBackend  # noqa: PLC0415

            return LibvirtBackend(settings, require_slice=require_slice)

        return Sandboxes(settings, Paths.from_environment(), connect, session)

    server = Server(open_sandboxes, protocol_out, version)

    def terminate(signum: int, _frame: object) -> None:
        # Codex follows SIGTERM with SIGKILL two seconds later; gc removes what remains.
        server.reap_all()
        os._exit(128 + signum)

    signal.signal(signal.SIGTERM, terminate)
    server.serve(protocol_in)
    return 0
