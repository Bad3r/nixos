# Copyright (c) 2026 Bad3r
"""MCP stdio front end of sbx.

Each tool is an operation of the registry in `ops`: the server checks a
call's arguments against the tool's schema and runs the operation's handler,
so a tool returns the document `sbx <verb> --json` prints. A screenshot also
comes back as an image content block for the client to display.
"""

import base64
import binascii
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
from io import BytesIO
from pathlib import Path
from typing import TYPE_CHECKING, BinaryIO, cast

from PIL import Image

from sbx import ops
from sbx.config import Settings, caller_session
from sbx.errors import SbxError
from sbx.results import ScreenshotResult
from sbx.sandboxes import open_sandboxes

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable

    from sbx.sandboxes import Sandboxes

# 2025-03-26 is left out: it requires JSON-RPC batches, which this server rejects.
PROTOCOL_VERSIONS = ("2025-11-25", "2025-06-18", "2024-11-05")
PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603
INSTRUCTIONS = (
    "Disposable VMs for unknown binaries, downloads, and untrusted repositories; "
    "the sbx skill says when to use them. Host paths sit under the git checkout of "
    "the directory the client started in, ~/trees, or $TMPDIR; relative paths "
    "resolve against that directory, so pass absolute ones."
)
# Clients cut long tool results, so a lower cap keeps `truncated` truthful.
OUTPUT_LIMIT = 64 * 1024

type Json = dict[str, object]


TOOLS = tuple(operation for operation in ops.OPERATIONS if operation.mcp_exposed)
TOOLS_BY_NAME = {tool.name: tool for tool in TOOLS}


def schema(param: ops.Param) -> Json:
    """Return the JSON schema of one argument."""
    match param.kind:
        case "integer":
            document: Json = {"type": "integer"}
        case "boolean":
            document = {"type": "boolean"}
        case "env":
            document = {"type": "object", "additionalProperties": {"type": "string"}}
        case "command":
            document = {"type": "array", "items": {"type": "string"}, "minItems": 1}
        case _ if param.repeatable:
            document = {"type": "array", "items": {"type": "string"}}
            if param.required:
                document["minItems"] = 1
        case _:
            document = {"type": "string"}
    document["description"] = param.description
    if param.enum:
        document["enum"] = list(param.enum)
    return document | dict(param.schema)


def definition(tool: ops.Operation) -> Json:
    """Return the tools/list entry of one operation."""
    params = [param for param in tool.params if param.mcp]
    return {
        "name": tool.name,
        "title": tool.title,
        "description": tool.description,
        "inputSchema": {
            "type": "object",
            "properties": {param.name: schema(param) for param in params},
            "required": [param.name for param in params if param.required],
            "additionalProperties": False,
        },
        "annotations": {
            "title": tool.title,
            "readOnlyHint": tool.read_only,
            "destructiveHint": tool.destructive,
            "openWorldHint": tool.open_world,
        },
    }


def _usage(message: str) -> SbxError:
    return SbxError(message, code="usage")


def _strings(tool: str, param: ops.Param, value: object) -> list[str]:
    if not isinstance(value, list) or not all(
        isinstance(item, str) for item in cast("list[object]", value)
    ):
        msg = f"{tool}: '{param.name}' must be a list of strings"
        raise _usage(msg)
    items = cast("list[str]", value)
    if not items and (param.required or param.kind == "command"):
        msg = f"{tool}: '{param.name}' needs at least one item"
        raise _usage(msg)
    return items


def _env(tool: str, param: ops.Param, value: object) -> list[str]:
    if not isinstance(value, dict) or not all(
        isinstance(item, str) for item in cast("dict[object, object]", value).values()
    ):
        msg = f"{tool}: '{param.name}' must be an object of strings"
        raise _usage(msg)
    return [f"{key}={item}" for key, item in cast("dict[str, str]", value).items()]


def _string(tool: str, param: ops.Param, value: object) -> str | bytes:
    if not isinstance(value, str):
        msg = f"{tool}: '{param.name}' must be a string"
        raise _usage(msg)
    if param.enum and value not in param.enum:
        msg = f"{tool}: '{param.name}' must be one of {', '.join(param.enum)}"
        raise _usage(msg)
    if param.kind != "base64":
        return value
    try:
        return base64.b64decode(value, validate=True)
    except binascii.Error as error:
        msg = f"{tool}: '{param.name}' is not base64"
        raise _usage(msg) from error


def _decode(tool: str, param: ops.Param, value: object) -> object:
    """Check one argument against its schema and return the value its handler reads."""
    if param.kind == "boolean":
        if not isinstance(value, bool):
            msg = f"{tool}: '{param.name}' must be a boolean"
            raise _usage(msg)
        return value
    if param.kind == "integer":
        if isinstance(value, bool) or not isinstance(value, int):
            msg = f"{tool}: '{param.name}' must be an integer"
            raise _usage(msg)
        return value
    if param.kind == "env":
        return _env(tool, param, value)
    if param.kind == "command" or param.repeatable:
        return _strings(tool, param, value)
    return _string(tool, param, value)


def parse_arguments(tool: ops.Operation, given: object) -> ops.Args:
    """Check a call's arguments against the tool's schema; null is the same as left out."""
    if given is None:
        given = {}
    if not isinstance(given, dict):
        msg = "arguments must be an object"
        raise _usage(msg)
    fields = cast("dict[str, object]", given)
    params = {param.name: param for param in tool.params if param.mcp}
    unknown = sorted(set(fields) - set(params))
    if unknown:
        msg = f"{tool.name}: unknown arguments: {', '.join(unknown)}"
        raise _usage(msg)
    values = {
        name: _decode(tool.name, params[name], value)
        for name, value in fields.items()
        if value is not None
    }
    for param in params.values():
        if param.required and param.name not in values:
            msg = f"{tool.name}: '{param.name}' is required"
            raise _usage(msg)
    if tool.one_of and sum(values.get(name) not in (None, False) for name in tool.one_of) != 1:
        names = [f"'{name}'" for name in tool.one_of]
        msg = f"{tool.name}: give exactly one of {', '.join(names)}"
        raise _usage(msg)
    return ops.Args(tool, values)


def session_of(meta: object) -> str | None:
    """Return the agent session behind one call."""
    # Codex clears the server's environment but names its session in each call,
    # which subagents share, unlike their threads; before 0.155 it sent only the
    # thread. Claude Code exports CLAUDE_CODE_SESSION_ID when it starts the server.
    if isinstance(meta, dict):
        fields = cast("dict[str, object]", meta)
        for key in ("sessionId", "threadId"):
            value = fields.get(key)
            if isinstance(value, str) and value:
                return f"codex:{value}"
    return caller_session()


def _text(document: object, *, error: bool) -> Json:
    text = json.dumps(document, separators=(",", ":"))
    return {"content": [{"type": "text", "text": text}], "isError": error}


def _screenshot(result: ScreenshotResult) -> Json:
    path = Path(result.path)
    if result.mime == "image/png":
        data = path.read_bytes()
    else:
        with Image.open(path, formats=("PPM",)) as image, BytesIO() as output:
            image.save(output, format="PNG")
            data = output.getvalue()
    return {
        "content": [
            {"type": "text", "text": json.dumps(result.as_json(), separators=(",", ":"))},
            {
                "type": "image",
                "data": base64.b64encode(data).decode("ascii"),
                "mimeType": "image/png",
            },
        ],
        "isError": False,
    }


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
        # Set at the end of input, which ends every wait for capacity.
        self._closed = threading.Event()

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
                self._reply(request_id, {"tools": [definition(tool) for tool in TOOLS]})
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
        self,
        tool: ops.Operation,
        arguments: object,
        session: str | None,
        record: Call | None = None,
    ) -> Json:
        """Run one tool and return its result; sbx refusals are tool errors."""
        try:
            args = parse_arguments(tool, arguments)
        except SbxError as error:
            return _text(ops.fail(error).as_json(), error=True)
        ctx = ops.Ctx(session)
        if record is not None:
            ctx = ops.Ctx(
                session,
                token=record.token,
                cancelled=lambda: record.cancelled or self._closed.is_set(),
            )
        outcome = ops.invoke(tool, self._open, args, ctx)
        if isinstance(outcome, ops.Failure):
            return _text(outcome.as_json(), error=True)
        if isinstance(outcome, ScreenshotResult):
            try:
                return _screenshot(outcome)
            except OSError as error:
                return _text(ops.fail(error).as_json(), error=True)
        return _text(outcome.as_json(), error=False)

    def _call(
        self, request_id: object, tool: ops.Operation, arguments: object, session: str | None
    ) -> None:
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
        """Handle input until it ends, which ends every wait for capacity, then join the calls."""
        for line in lines:
            if line.strip():
                self.receive(line)
        self._closed.set()
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

    server = Server(functools.partial(open_sandboxes, settings), protocol_out, version)

    def terminate(signum: int, _frame: object) -> None:
        # Codex follows SIGTERM with SIGKILL two seconds later; gc removes what remains.
        server.reap_all()
        os._exit(128 + signum)

    signal.signal(signal.SIGTERM, terminate)
    server.serve(protocol_in)
    return 0
