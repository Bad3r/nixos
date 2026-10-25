# Copyright (c) 2026 Bad3r
"""Command line of sbx."""

import argparse
import json
import sys
from typing import TYPE_CHECKING, NoReturn, cast

from sbx import completion, journal, sleep, vsock
from sbx.config import Paths, Settings, caller_session, parse_duration
from sbx.errors import SbxError, error_document
from sbx.execution import exec_options
from sbx.model import ENCODINGS, FLAVOURS, NETS, Backend, ExecOptions, ExecResult, Request
from sbx.sandboxes import Sandboxes
from sbx.shares import SHARED, Shares

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence
    from pathlib import Path

USAGE_EXIT = 2


class Parser(argparse.ArgumentParser):
    """Raise usage errors so --json can report them."""

    def error(self, message: str) -> NoReturn:
        """Turn an argparse failure into an SbxError."""
        msg = f"{self.prog}: {message}"
        raise SbxError(msg, code="usage")


def _command(args: argparse.Namespace) -> list[str]:
    command: list[str] = args.command
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


def _exec_flags(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--timeout", help="command timeout such as 10m")
    parser.add_argument("--cwd", help="absolute guest directory; default the user's home")
    parser.add_argument(
        "--env",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="set a variable after the guest profile; repeatable",
    )
    parser.add_argument("--user", help="guest user; default root")
    parser.add_argument(
        "--stdin", metavar="FILE|-", help="feed a file, or sbx's stdin, up to 1 MiB"
    )
    parser.add_argument(
        "--output-encoding",
        choices=ENCODINGS,
        default="text",
        help="--json output as UTF-8 text, or base64 of the raw bytes",
    )
    # The MCP server sets the stdin bytes directly.
    parser.set_defaults(stdin_data=None)


def _exec_options(sandboxes: Sandboxes, args: argparse.Namespace) -> ExecOptions:
    stdin: bytes | None = args.stdin_data
    if stdin is None and args.stdin is not None:
        stdin = sandboxes.read_input(args.stdin)
    return exec_options(
        timeout=_timeout(args.timeout), cwd=args.cwd, env=args.env, user=args.user, stdin=stdin
    )


def build_parser() -> argparse.ArgumentParser:  # noqa: PLR0915
    """Describe every verb."""
    parser = Parser(prog="sbx", description="Disposable agent sandboxes on qemu:///session.")
    parser.add_argument("--json", action="store_true", help="print JSON, errors included")
    common = Parser(add_help=False)
    common.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    verbs = parser.add_subparsers(dest="verb", required=True, parser_class=Parser)

    create_flags = Parser(add_help=False)
    # Cloud and Windows bases come from the settings, which load after parsing.
    create_flags.add_argument(
        "base", help=f"{', '.join(FLAVOURS)}, a prepared cloud base, or a Windows base"
    )
    create_flags.add_argument("--name", help="sandbox name; default <base>-<6 hex>")
    create_flags.add_argument(
        "--net", choices=NETS, default="none", help="none: no NIC; egress: DHCP on the sbx bridge"
    )
    create_flags.add_argument("--mem", help="memory such as 2G")
    create_flags.add_argument("--cpus", type=int)
    create_flags.add_argument("--ttl", help="lifetime such as 30m or 2h")
    create_flags.add_argument(
        "--wait", help="queue up to this long, such as 30m, when the host's sandbox limits are full"
    )
    create_flags.add_argument(
        "--gui", action="store_true", help="the base's GUI variant, with more default memory"
    )

    verbs.add_parser("create", parents=[common, create_flags], help="start a sandbox")

    run = verbs.add_parser(
        "run", parents=[common, create_flags], help="create, copy in, exec, copy out, destroy"
    )
    run.add_argument("--in", dest="inputs", action="append", default=[], metavar="PATH")
    run.add_argument("--out", dest="outputs", action="append", default=[], metavar="GUEST_PATH")
    run.add_argument("--to", help="host directory for --out")
    _exec_flags(run)

    execute = verbs.add_parser("exec", parents=[common], help="run a command in a sandbox")
    execute.add_argument("name")
    _exec_flags(execute)

    copy = verbs.add_parser("cp", parents=[common], help="copy between host and sandbox")
    copy.add_argument("source", help="host path or <name>:<path>")
    copy.add_argument(
        "destination", nargs="?", help="<name>:<path>, or a host path; default the xfer directory"
    )

    destroy = verbs.add_parser("destroy", parents=[common], help="remove sandboxes")
    target = destroy.add_mutually_exclusive_group(required=True)
    target.add_argument("name", nargs="?")
    target.add_argument("--mine", action="store_true")
    target.add_argument("--expired", action="store_true")

    listing = verbs.add_parser("list", parents=[common], help="list sandboxes")
    listing.add_argument("--mine", action="store_true")

    info = verbs.add_parser("info", parents=[common], help="describe one sandbox")
    info.add_argument("name")

    screenshot = verbs.add_parser("screenshot", parents=[common], help="capture the display")
    screenshot.add_argument("name")
    screenshot.add_argument("--ocr", action="store_true", help="add the text tesseract reads")

    key = verbs.add_parser("key", parents=[common], help="press keys on a GUI sandbox")
    key.add_argument("name")
    key.add_argument("keys", nargs="+", metavar="KEY", help="a key or chord such as ctrl+alt+t")

    typing = verbs.add_parser("type", parents=[common], help="type text on a GUI sandbox")
    typing.add_argument("name")
    typing.add_argument("text", help="US-layout text; newline presses enter")

    # No --json between share and its verb, like base.
    share = verbs.add_parser("share", help="attach or detach a runtime virtiofs share")
    share_verbs = share.add_subparsers(dest="share_verb", required=True, parser_class=Parser)
    for verb, text in (
        ("attach", "hot-plug a share into a running sandbox"),
        ("detach", "remove a share; fails while the guest still holds it"),
    ):
        action = share_verbs.add_parser(verb, parents=[common], help=text)
        action.add_argument("name")
        action.add_argument(
            "share",
            help=f"{SHARED} (read-write) or a workloads.grants.sandboxShares name (read-only)",
        )

    gc = verbs.add_parser(
        "gc",
        parents=[common],
        help=f"remove expired and orphaned sandboxes; detach {SHARED} past the disk cap",
    )
    gc.add_argument("--dry-run", action="store_true")

    # No --json between base and its verb, so permission rules see one spelling.
    base = verbs.add_parser("base", help="list, build, or prepare bases")
    base_verbs = base.add_subparsers(dest="base_verb", required=True, parser_class=Parser)
    base_verbs.add_parser("list", parents=[common])
    build = base_verbs.add_parser("build", parents=[common])
    build.add_argument("flavour", help=", ".join(FLAVOURS))
    prepare = base_verbs.add_parser("prepare", parents=[common])
    prepare.add_argument("image", help="a cloud image from the settings")

    host_sleep = verbs.add_parser(
        "sleep",
        parents=[common],
        help="host sleep hook only, not for agents: pause, resume, save, or restore sandboxes",
    )
    host_sleep.add_argument("phase", choices=sleep.PHASES)

    proxy = verbs.add_parser(
        "vsock", help="grant listeners of sandboxes without a network, for workloads grant"
    )
    proxy_verbs = proxy.add_subparsers(dest="vsock_verb", required=True, parser_class=Parser)
    proxy_verbs.add_parser("serve", help="run the proxy; sbx-vsock.service starts it")
    proxy_verbs.add_parser("sync", parents=[common], help="apply the grant list now")
    return parser


def _request(sandboxes: Sandboxes, args: argparse.Namespace) -> Request:
    return sandboxes.request(
        args.base,
        name=args.name,
        net=args.net,
        memory=args.mem,
        cpus=args.cpus,
        ttl=args.ttl,
        gui=args.gui,
        wait=args.wait,
    )


def _print_exec(result: ExecResult) -> int:
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    if result.truncated:
        print("sbx: output truncated", file=sys.stderr)
    if result.timed_out:
        print("sbx: the command timed out", file=sys.stderr)
    if result.transport_error is not None:
        print(f"sbx: {result.transport_error}", file=sys.stderr)
    return result.status()


def _run(
    sandboxes: Sandboxes, args: argparse.Namespace, *, as_json: bool, token: str | None
) -> tuple[object, int]:
    command = _command(args)
    if args.outputs and args.to is None:
        msg = "--out needs --to"
        raise SbxError(msg, code="usage")
    if args.to is not None and not args.outputs:
        msg = "--to needs --out"
        raise SbxError(msg, code="usage")
    options = _exec_options(sandboxes, args)
    result = sandboxes.run_once(
        _request(sandboxes, args),
        command,
        options,
        inputs=args.inputs,
        outputs=args.outputs,
        to=args.to,
        attached=not as_json,
        token=token,
    )
    code = None if result.execution is None else result.execution.status()
    if not as_json:
        if result.execution is not None:
            _print_exec(result.execution)
        for entry in result.failed_outputs():
            error = cast("dict[str, object]", entry["error"])
            print(f"sbx: copy out of {entry['from']} failed: {error['message']}", file=sys.stderr)
        if result.cleanup_error is not None:
            print(f"sbx: cleanup failed: {result.cleanup_error}", file=sys.stderr)
    if code is None or result.failed_phase() is not None:
        raise result.incomplete(args.output_encoding)
    return (result.as_json(args.output_encoding) if as_json else None), code


def dispatch(  # noqa: C901, PLR0911, PLR0912
    sandboxes: Sandboxes,
    args: argparse.Namespace,
    *,
    as_json: bool,
    attach: Callable[[], Backend] | None = None,
    token: str | None = None,
) -> tuple[object, int]:
    """Run one verb and return its result and exit code; `token` marks a run's sandbox."""
    match args.verb:
        case "create":
            return sandboxes.create(_request(sandboxes, args)), 0
        case "run":
            return _run(sandboxes, args, as_json=as_json, token=token)
        case "exec":
            command = _command(args)
            options = _exec_options(sandboxes, args)
            if as_json or sandboxes.agent_only(args.name):
                result = sandboxes.exec_capture(args.name, command, options)
                if as_json:
                    return result.as_json(args.output_encoding), result.status()
                return None, _print_exec(result)
            attached = sandboxes.exec_attached(args.name, command, options)
            return None, _print_exec(attached)
        case "cp":
            return sandboxes.copy(args.source, args.destination), 0
        case "destroy":
            if args.name is not None:
                return sandboxes.destroy(args.name), 0
            return sandboxes.destroy_where(mine=args.mine, expired=args.expired), 0
        case "list":
            return sandboxes.listing(mine=args.mine), 0
        case "info":
            return sandboxes.info(args.name), 0
        case "screenshot":
            return sandboxes.screenshot(args.name, ocr=args.ocr), 0
        case "key":
            return sandboxes.key(args.name, args.keys), 0
        case "type":
            return sandboxes.type_text(args.name, args.text), 0
        case "share":
            shares = Shares(sandboxes)
            if args.share_verb == "attach":
                return shares.attach(args.name, args.share), 0
            return shares.detach(args.name, args.share), 0
        case "gc":
            removed = sandboxes.gc(dry_run=args.dry_run)
            return removed + Shares(sandboxes).reclaim(dry_run=args.dry_run), 0
        case "base":
            if args.base_verb == "list":
                return sandboxes.base_list(), 0
            if args.base_verb == "prepare":
                return sandboxes.base_prepare(args.image), 0
            return sandboxes.base_build(args.flavour), 0
        case "sleep":
            if attach is None:
                msg = "sleep needs a connect that never starts the daemon"
                raise SbxError(msg, code="internal")
            actions, code = sleep.Sleep(sandboxes, sleep.state_dir(), attach, as_json=as_json).run(
                args.phase
            )
            return (actions if as_json else None), code
        case "vsock":
            if args.vsock_verb == "serve":
                vsock.serve(sandboxes.paths)
            return vsock.sync(vsock.control_path()), 0
        case _:
            msg = f"unknown verb {args.verb}"
            raise SbxError(msg, code="usage")


def _plain(result: object) -> None:
    if result is None:
        return
    if isinstance(result, list):
        for item in cast("list[object]", result):
            _plain(item)
        return
    if isinstance(result, dict):
        fields = cast("dict[str, object]", result)
        print(" ".join(f"{key}={value}" for key, value in fields.items() if value is not None))
        return
    print(result)


def split_command(arguments: Sequence[str]) -> tuple[list[str], list[str]]:
    """Separate sbx's own arguments from the guest command after the first --."""
    arguments = list(arguments)
    if "--" not in arguments:
        return arguments, []
    split = arguments.index("--")
    return arguments[:split], arguments[split + 1 :]


def main(settings_path: Path, argv: Sequence[str] | None = None) -> int:
    """Parse, run, print; failures exit non-zero, as JSON under --json."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    completion.autocomplete(parser, settings_path)
    if not arguments:
        parser.print_help()
        return 0
    leading, command = split_command(arguments)
    as_json = "--json" in leading
    try:
        args = parser.parse_args(leading)
        args.command = command
        settings = Settings.load(settings_path)

        def connect(require_slice: bool) -> Backend:  # noqa: FBT001
            from sbx.backend import LibvirtBackend  # noqa: PLC0415

            return LibvirtBackend(settings, require_slice=require_slice)

        def attach() -> Backend:
            from sbx.backend import LibvirtBackend  # noqa: PLC0415

            return LibvirtBackend(settings, require_slice=False, start=False)

        sandboxes = Sandboxes(settings, Paths.from_environment(), connect, caller_session())
        result, code = dispatch(sandboxes, args, as_json=as_json, attach=attach)
    except (SbxError, OSError) as error:
        code = error.code if isinstance(error, SbxError) else "os-error"
        journal.record(f"failed: {error}", code=code)
        if as_json:
            print(json.dumps({"error": error_document(error)}))
        else:
            print(f"sbx: {error}", file=sys.stderr)
        return USAGE_EXIT if code == "usage" else 1
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        _plain(result)
    return code
