# Copyright (c) 2026 Bad3r
"""The operations of sbx, which the CLI and the MCP server both serve.

Each Operation names its verb path, its parameters, and a handler. `cli`
builds its parser from the registry and `mcp` its tools; both call the
handler with checked arguments through `invoke`, which also journals a
failure and returns its error document.
"""

import dataclasses
import itertools
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Literal, cast

from sbx import journal, sleep, vsock
from sbx.config import parse_duration
from sbx.errors import SbxError, error_code, error_document
from sbx.execution import exec_options
from sbx.gui import TYPE_LIMIT
from sbx.model import ENCODINGS, FLAVOURS, NETS, SHARED
from sbx.results import Document, Result, Results
from sbx.sandboxes import running_daemon
from sbx.shares import Shares

if TYPE_CHECKING:
    from sbx.model import ExecOptions, Request
    from sbx.sandboxes import Sandboxes


# string and integer take one value; boolean is a switch; env is NAME=VALUE pairs,
# an object over MCP; command is the guest argv, after -- on the command line;
# base64 is bytes over MCP.
type Kind = Literal["string", "integer", "boolean", "env", "command", "base64"]


@dataclass(frozen=True)
class Param:
    """One argument of an operation, by the name its handler reads."""

    name: str
    help: str | None = None
    kind: Kind = "string"
    # The command-line option; None makes the argument positional.
    flag: str | None = None
    required: bool = False
    # A list of strings: an option given once per item, or a positional taking several.
    repeatable: bool = False
    enum: tuple[str, ...] = ()
    default: str | None = None
    metavar: str | None = None
    # The MCP description, where the command line's mentions flags.
    mcp_help: str | None = None
    # Extra JSON schema keywords the MCP tool advertises; the handler checks them itself.
    schema: Mapping[str, object] = field(default_factory=dict[str, object])
    cli: bool = True
    mcp: bool = True

    @property
    def description(self) -> str:
        """Return the MCP description."""
        return self.mcp_help or self.help or ""


@dataclass(frozen=True)
class Ctx:
    """Who calls an operation, and how."""

    session: str | None
    # A run's creation token, which its sandbox's metadata carries from define on.
    token: str | None = None
    # Polled while a create waits; the MCP server ends the wait of a cancelled call.
    cancelled: Callable[[], bool] = lambda: False
    # The caller's terminal takes a Linux command's stdio, as without --json.
    stdio_attached: bool = False


class Args:
    """Checked arguments of one call; a missing one takes its parameter's default."""

    def __init__(self, operation: Operation, values: Mapping[str, object]) -> None:
        """Bind the values to the operation they were checked against."""
        self.operation = operation
        self._values = dict(values)
        # The parameters the handler read, which the exposure test compares to the declared.
        self.read: set[str] = set()

    def _value(self, name: str) -> object:
        param = self.operation.param(name)
        if param is None:
            msg = f"{self.operation.name} has no parameter '{name}'"
            raise SbxError(msg, code="internal")
        self.read.add(name)
        value = self._values.get(name)
        return param.default if value is None else value

    def _wrong(self, name: str, kind: str) -> SbxError:
        msg = f"'{name}' of {self.operation.name} is no {kind}"
        return SbxError(msg, code="internal")

    def text(self, name: str) -> str:
        """Return a required string."""
        value = self._value(name)
        if not isinstance(value, str):
            raise self._wrong(name, "string")
        return value

    def optional(self, name: str) -> str | None:
        """Return a string, or None when it was not given."""
        value = self._value(name)
        if value is not None and not isinstance(value, str):
            raise self._wrong(name, "string")
        return value

    def flag(self, name: str) -> bool:
        """Return a switch."""
        value = self._value(name)
        if value is not None and not isinstance(value, bool):
            raise self._wrong(name, "boolean")
        return bool(value)

    def integer(self, name: str) -> int | None:
        """Return an integer, or None when it was not given."""
        value = self._value(name)
        if value is not None and (isinstance(value, bool) or not isinstance(value, int)):
            raise self._wrong(name, "integer")
        return value

    def strings(self, name: str) -> list[str]:
        """Return a list of strings, empty when none was given."""
        value = self._value(name)
        if value is None:
            return []
        if not isinstance(value, list) or not all(
            isinstance(item, str) for item in cast("list[object]", value)
        ):
            raise self._wrong(name, "list of strings")
        return cast("list[str]", value)

    def data(self, name: str) -> bytes | None:
        """Return bytes, or None when they were not given."""
        value = self._value(name)
        if value is not None and not isinstance(value, bytes):
            raise self._wrong(name, "byte string")
        return value


type Handler = Callable[[Sandboxes, Args, Ctx], Result]


@dataclass(frozen=True)
class Operation:
    """One verb: the parser of `sbx <path>` and, when `mcp_exposed`, an MCP tool."""

    path: tuple[str, ...]
    help: str | None
    handler: Handler
    params: tuple[Param, ...] = ()
    title: str = ""
    description: str = ""
    mcp_exposed: bool = True
    read_only: bool = False
    destructive: bool = False
    open_world: bool = False
    # Exactly one of these parameters is given.
    one_of: tuple[str, ...] = ()
    takes_json: bool = True

    @property
    def name(self) -> str:
        """Return the MCP tool name, the path joined by underscores."""
        return "_".join(self.path)

    def param(self, name: str) -> Param | None:
        """Return one parameter by name."""
        return next((param for param in self.params if param.name == name), None)


@dataclass(frozen=True)
class Failure:
    """A refused or failed call, after its journal entry."""

    error: SbxError | OSError
    # What a run did before it failed, for the CLI's plain-text report.
    partial: Result | None = None

    @property
    def code(self) -> str:
        """Return the stable error code."""
        return error_code(self.error)

    def as_json(self) -> dict[str, object]:
        """Return the error document."""
        return {"error": error_document(self.error)}


def fail(error: SbxError | OSError, partial: Result | None = None) -> Failure:
    """Journal a failed call and return it."""
    journal.record(f"failed: {error}", code=error_code(error))
    return Failure(error, partial)


def invoke(
    operation: Operation,
    open_sandboxes: Callable[[str | None], Sandboxes],
    args: Args,
    ctx: Ctx,
) -> Result | Failure:
    """Run one operation for the caller `ctx` names; sbx refusals and OS errors are failures."""
    try:
        sandboxes = open_sandboxes(ctx.session)
        sandboxes.cancelled = ctx.cancelled
        result = operation.handler(sandboxes, args, ctx)
    except (SbxError, OSError) as error:
        return fail(error)
    error = result.error()
    return result if error is None else fail(error, result)


# Handlers


def _command(args: Args) -> list[str]:
    command = args.strings("command")
    if not command:
        msg = "give the command after --"
        raise SbxError(msg, code="usage")
    return command


def _timeout(value: str | None) -> float | None:
    if value is None:
        return None
    seconds = parse_duration(value)
    if seconds == 0:
        msg = "--timeout takes a duration above zero; leave it out for no timeout"
        raise SbxError(msg, code="invalid-argument")
    return float(seconds)


def _exec_options(sandboxes: Sandboxes, args: Args) -> ExecOptions:
    text, encoded, path = (
        args.optional("stdin"),
        args.data("stdin_base64"),
        args.optional("stdin_path"),
    )
    timeout, cwd, env, user = (
        args.optional("timeout"),
        args.optional("cwd"),
        args.strings("env"),
        args.optional("user"),
    )
    if text is not None and encoded is not None:
        msg = "give one of 'stdin' and 'stdin_base64'"
        raise SbxError(msg, code="usage")
    stdin = text.encode() if text is not None else encoded
    if stdin is None and path is not None:
        stdin = sandboxes.read_input(path)
    return exec_options(timeout=_timeout(timeout), cwd=cwd, env=env, user=user, stdin=stdin)


def _request(sandboxes: Sandboxes, args: Args) -> Request:
    return sandboxes.request(
        args.text("base"),
        name=args.optional("name"),
        net=args.text("net"),
        memory=args.optional("mem"),
        cpus=args.integer("cpus"),
        ttl=args.optional("ttl"),
        gui=args.flag("gui"),
        wait=args.optional("wait"),
    )


def _create(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return sandboxes.create(_request(sandboxes, args))


def _run(sandboxes: Sandboxes, args: Args, ctx: Ctx) -> Result:
    encoding = args.text("encoding")
    command = _command(args)
    request = _request(sandboxes, args)
    plan = sandboxes.plan_run(request, args.strings("in"), args.strings("out"), args.optional("to"))
    options = _exec_options(sandboxes, args)
    result = sandboxes.run_once(
        request, plan, command, options, attached=ctx.stdio_attached, token=ctx.token
    )
    if result.execution is not None:
        result.execution = dataclasses.replace(result.execution, encoding=encoding)
    return result


def _exec(sandboxes: Sandboxes, args: Args, ctx: Ctx) -> Result:
    name, encoding = args.text("name"), args.text("encoding")
    command = _command(args)
    options = _exec_options(sandboxes, args)
    if ctx.stdio_attached and not sandboxes.agent_only(name):
        result = sandboxes.exec_attached(name, command, options)
    else:
        result = sandboxes.exec_capture(name, command, options)
    return dataclasses.replace(result, encoding=encoding)


def _copy(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return sandboxes.copy(args.text("source"), args.optional("destination"))


def _destroy(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    name, mine, expired = args.optional("name"), args.flag("mine"), args.flag("expired")
    if name is not None:
        return Document(sandboxes.destroy(name))
    return Document(sandboxes.destroy_where(mine=mine, expired=expired))


def _list(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return Results(sandboxes.listing(mine=args.flag("mine")))


def _info(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return sandboxes.info(args.text("name"))


def _screenshot(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return sandboxes.screenshot(args.text("name"), ocr=args.flag("ocr"), to=args.optional("to"))


def _key(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return sandboxes.key(args.text("name"), args.strings("keys"))


def _type(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return sandboxes.type_text(args.text("name"), args.text("text"))


def _share_attach(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return Shares(sandboxes).attach(args.text("name"), args.text("share"))


def _share_detach(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return Shares(sandboxes).detach(args.text("name"), args.text("share"))


def _gc(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    dry_run = args.flag("dry_run")
    removed = sandboxes.gc(dry_run=dry_run)
    return Results([*removed, *Shares(sandboxes).reclaim(dry_run=dry_run)])


def _base_list(sandboxes: Sandboxes, _args: Args, _ctx: Ctx) -> Result:
    return Document(sandboxes.base_list())


def _base_build(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return Document(sandboxes.base_build(args.text("flavour")))


def _base_prepare(sandboxes: Sandboxes, args: Args, _ctx: Ctx) -> Result:
    return Document(sandboxes.base_prepare(args.text("image")))


def _sleep(sandboxes: Sandboxes, args: Args, ctx: Ctx) -> Result:
    hook = sleep.Sleep(
        sandboxes,
        sleep.state_dir(),
        lambda: running_daemon(sandboxes.settings),
        as_json=not ctx.stdio_attached,
    )
    actions, code = hook.run(args.text("phase"))
    # In plain text the hook prints each action as it happens.
    return Document(None if ctx.stdio_attached else actions, code)


def _vsock_serve(sandboxes: Sandboxes, _args: Args, _ctx: Ctx) -> Result:
    vsock.serve(sandboxes.paths)


def _vsock_sync(_sandboxes: Sandboxes, _args: Args, _ctx: Ctx) -> Result:
    return Document(vsock.sync(vsock.control_path()))


# Registry

NAME = Param("name", "sandbox name", required=True)
CREATE_PARAMS = (
    # Cloud and Windows bases come from the settings, so create checks the name.
    Param(
        "base",
        f"{', '.join(FLAVOURS)}, a prepared cloud base, or a Windows base",
        required=True,
        mcp_help=(
            f"base to boot: {', '.join(FLAVOURS)}, a prepared cloud base, "
            "or a Windows base that base_list reports"
        ),
    ),
    Param("name", "sandbox name; default <base>-<6 hex>", flag="--name"),
    Param(
        "net",
        "none: no NIC; egress: DHCP on the sbx bridge",
        flag="--net",
        enum=NETS,
        default="none",
        mcp_help="network; default none",
    ),
    Param("mem", "memory such as 2G", flag="--mem"),
    Param("cpus", "vCPUs", kind="integer", flag="--cpus", schema={"minimum": 1}),
    Param("ttl", "lifetime such as 30m or 2h", flag="--ttl"),
    Param(
        "wait",
        "queue up to this long, such as 30m, when the host's sandbox limits are full",
        flag="--wait",
    ),
    Param("gui", "the base's GUI variant, with more default memory", kind="boolean", flag="--gui"),
)
EXEC_PARAMS = (
    Param(
        "timeout",
        "command timeout such as 10m",
        flag="--timeout",
        mcp_help="command timeout such as 10m; then SIGTERM, and SIGKILL 5 s later",
    ),
    Param("cwd", "absolute guest directory; default the user's home", flag="--cwd"),
    Param(
        "env",
        "set a variable after the guest profile; repeatable",
        kind="env",
        flag="--env",
        metavar="NAME=VALUE",
        mcp_help="variables set after the guest profile",
    ),
    Param("user", "guest user; default root", flag="--user"),
    Param(
        "stdin_path",
        "feed a file, or sbx's stdin, up to 1 MiB",
        flag="--stdin",
        metavar="FILE|-",
        mcp=False,
    ),
    Param(
        "encoding",
        "--json output as UTF-8 text, or base64 of the raw bytes",
        flag="--output-encoding",
        enum=ENCODINGS,
        default="text",
        mcp_help=(
            "stdout and stderr as text, with *_lossy set where invalid UTF-8 was replaced, "
            "or as base64 of the raw bytes; default text"
        ),
    ),
    Param("stdin", "text fed to the command's stdin, up to 1 MiB", cli=False),
    Param(
        "stdin_base64",
        "bytes fed to the command's stdin, base64, up to 1 MiB",
        kind="base64",
        cli=False,
    ),
    Param(
        "command",
        "argv of the guest command, run without a shell; wrap pipes in sh -c",
        kind="command",
        required=True,
    ),
)
SHARE_PARAMS = (
    NAME,
    Param(
        "share",
        f"{SHARED} (read-write) or a workloads.grants.sandboxShares name (read-only)",
        required=True,
    ),
)

OPERATIONS = (
    Operation(
        ("create",),
        "start a sandbox",
        _create,
        CREATE_PARAMS,
        "Create a sandbox",
        "Start a sandbox and wait until SSH answers; returns its name, CID, and TTL. "
        "With wait, a create the host's limits refuse queues for capacity first.",
        open_world=True,
    ),
    Operation(
        ("run",),
        "create, copy in, exec, copy out, destroy",
        _run,
        (
            *CREATE_PARAMS,
            Param(
                "in",
                "host paths copied into /root/ or C:\\sbx\\",
                flag="--in",
                repeatable=True,
                metavar="PATH",
            ),
            Param(
                "out",
                "guest paths copied to 'to' afterwards",
                flag="--out",
                repeatable=True,
                metavar="GUEST_PATH",
            ),
            Param(
                "to", "host directory for --out", flag="--to", mcp_help="host directory for 'out'"
            ),
            *EXEC_PARAMS,
        ),
        "Run a command in a one-shot sandbox",
        "Create a sandbox, copy inputs to /root/ (C:\\sbx\\ on Windows), run the command, "
        "copy outputs out, and destroy the sandbox even when a step fails; returns "
        "{sandbox, phases, in, exec, out, cleanup, failure}, with exec shaped as the exec "
        "tool's result. A failed copy in, a transport error, a failed copy out, or a failed "
        "cleanup is a tool error with code run-incomplete whose run field holds that whole "
        "document, so exec still carries the command's result. With wait, a run the host's "
        "limits refuse queues for capacity first.",
        open_world=True,
    ),
    Operation(
        ("exec",),
        "run a command in a sandbox",
        _exec,
        (NAME, *EXEC_PARAMS),
        "Run a command in a sandbox",
        "Run a command through the guest agent; returns {exit_code, signal, timed_out, "
        "killed, transport_error, duration_s, stdout, stderr, stdout_lossy, stderr_lossy, "
        "truncated}. A failing guest "
        "command is no tool error: exit_code is its status, or null with signal set when a "
        "signal ended it. timed_out means the timeout passed and sbx sent SIGTERM, then "
        "SIGKILL; transport_error means the guest agent stopped answering mid-command. "
        "The command runs as root in /root with HOME=/root unless user, cwd, or env say "
        "otherwise; Windows takes none of the three.",
    ),
    Operation(
        ("cp",),
        "copy between host and sandbox",
        _copy,
        (
            Param("source", "host path or <name>:<path>", required=True),
            Param(
                "destination",
                "<name>:<path>, or a host path; default the xfer directory",
                mcp_help="<name>:<path> or a host path",
            ),
        ),
        "Copy between host and sandbox",
        "Copy a file or directory; one side is <name>:<path>. Without a destination a copy "
        "out lands in the sandbox's xfer directory; copies out never overwrite.",
    ),
    Operation(
        ("destroy",),
        "remove sandboxes",
        _destroy,
        (
            Param("name", "sandbox name"),
            Param(
                "mine",
                "sandboxes of this agent session and its subagents",
                kind="boolean",
                flag="--mine",
            ),
            Param("expired", "sandboxes past their TTL", kind="boolean", flag="--expired"),
        ),
        "Destroy sandboxes",
        "Stop and delete one sandbox, every sandbox of this agent session, or every expired "
        "one; give exactly one of name, mine, and expired. Returns the destroyed names.",
        destructive=True,
        one_of=("name", "mine", "expired"),
    ),
    Operation(
        ("list",),
        "list sandboxes",
        _list,
        (
            Param(
                "mine",
                "only sandboxes of this agent session and its subagents",
                kind="boolean",
                flag="--mine",
            ),
        ),
        "List sandboxes",
        "Describe every sandbox: state, base, CID, TTL left, session, and xfer directory; "
        "creates waiting for capacity follow with state queued and their position.",
        read_only=True,
    ),
    Operation(
        ("info",),
        "describe one sandbox",
        _info,
        (NAME,),
        "Describe a sandbox",
        "Describe one sandbox as list does.",
        read_only=True,
    ),
    Operation(
        ("screenshot",),
        "capture the display",
        _screenshot,
        (
            NAME,
            Param("ocr", "add the text tesseract reads", kind="boolean", flag="--ocr"),
            Param(
                "to",
                "host directory, or a new file, for the image; default the xfer directory",
                flag="--to",
            ),
        ),
        "Capture a sandbox display",
        "Return the display as a PNG image content block alongside its saved path and MIME type. "
        "Each capture gets its own file in the sandbox's xfer directory, which destroy removes, "
        "or under 'to', which keeps it. Set ocr to also return the text tesseract reads in the "
        "text field.",
    ),
    Operation(
        ("key",),
        "press keys on a GUI sandbox",
        _key,
        (
            NAME,
            Param(
                "keys",
                "a key or chord such as ctrl+alt+t",
                required=True,
                repeatable=True,
                metavar="KEY",
                mcp_help="keys or chords such as enter or ctrl+alt+t, pressed in turn",
            ),
        ),
        "Press keys in a sandbox",
        "Press each key or chord in turn on the display of a sandbox with a GUI base; "
        "returns {sandbox, keys}.",
    ),
    Operation(
        ("type",),
        "type text on a GUI sandbox",
        _type,
        (
            NAME,
            Param(
                "text",
                "US-layout text; newline presses enter",
                required=True,
                schema={"maxLength": TYPE_LIMIT},
            ),
        ),
        "Type text in a sandbox",
        "Type text as US-layout key presses on the display of a sandbox with a GUI base; "
        "returns {sandbox, characters}. The journal records only the text's length.",
    ),
    Operation(
        ("share", "attach"),
        "hot-plug a share into a running sandbox",
        _share_attach,
        SHARE_PARAMS,
        "Attach a share to a sandbox",
        "Hot-plug a virtiofs share into a running Linux sandbox until it is detached or "
        f"stops: {SHARED}, the sandbox's own read-write directory, or a declared "
        "read-only host directory. Returns {sandbox, tag, read_only, host_path, "
        "attached}; the guest mounts it with mount -t virtiofs <tag> <directory>.",
    ),
    Operation(
        ("share", "detach"),
        "remove a share; fails while the guest still holds it",
        _share_detach,
        SHARE_PARAMS,
        "Detach a share from a sandbox",
        "Remove a share and wait until the guest releases it; returns the share as "
        "share_attach does, with attached false. A share the guest still holds is "
        "a detach-pending error; unmount it in the guest first.",
    ),
    Operation(
        ("gc",),
        f"remove expired and orphaned sandboxes; detach {SHARED} past the disk cap",
        _gc,
        (Param("dry_run", "report without removing", kind="boolean", flag="--dry-run"),),
        "Remove expired and orphaned sandboxes",
        "Remove sandboxes past their TTL, shut-off ones, and orphaned domains or directories; "
        "past the disk cap or free-space floor, detach every shared directory.",
        destructive=True,
    ),
    Operation(
        ("base", "list"),
        "report each base and whether it is built",
        _base_list,
        (),
        "List bases",
        "Report each base and whether it is built.",
        read_only=True,
    ),
    Operation(
        ("base", "build"),
        "build a Nix base offline from the configured flake",
        _base_build,
        (
            Param(
                "flavour",
                ", ".join(FLAVOURS),
                required=True,
                mcp_help="base to build",
                # The verb itself explains why a cloud or Windows base is not built.
                schema={"enum": list(FLAVOURS)},
            ),
        ),
        "Build a base",
        "Build a Nix base offline from the configured flake; create needs it first.",
    ),
    Operation(
        ("base", "prepare"),
        "provision a cloud base from its pinned image; the owner runs it",
        _base_prepare,
        (Param("image", "a cloud image from the settings", required=True),),
        mcp_exposed=False,
    ),
    Operation(
        ("sleep",),
        "host sleep hook only, not for agents: pause, resume, save, or restore sandboxes",
        _sleep,
        (Param("phase", enum=sleep.PHASES, required=True),),
        mcp_exposed=False,
    ),
    Operation(
        ("vsock", "serve"),
        "run the proxy; sbx-vsock.service starts it",
        _vsock_serve,
        mcp_exposed=False,
        takes_json=False,
    ),
    Operation(
        ("vsock", "sync"),
        "apply the grant list now",
        _vsock_sync,
        mcp_exposed=False,
    ),
)
# Verbs that only group others: share and base take no --json before their verb,
# so permission rules see one spelling.
GROUPS = {
    "share": "attach or detach a runtime virtiofs share",
    "base": "list, build, or prepare bases",
    "vsock": "grant listeners of sandboxes without a network, for workloads grant",
}
OPERATIONS_BY_NAME = {operation.name: operation for operation in OPERATIONS}


def grouped() -> itertools.groupby[tuple[str, ...], Operation]:
    """Return the operations by their group's path, () for top-level verbs, in registry order."""
    return itertools.groupby(OPERATIONS, key=lambda operation: operation.path[:-1])
