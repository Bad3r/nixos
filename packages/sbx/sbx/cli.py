# Copyright (c) 2026 Bad3r
"""Command line of sbx."""

import argparse
import json
import sys
from typing import TYPE_CHECKING, NoReturn, cast

from sbx import journal
from sbx.core import (
    FLAVOURS,
    NETS,
    Backend,
    ExecResult,
    Paths,
    Request,
    Sandboxes,
    SbxError,
    Settings,
    caller_session,
    parse_duration,
)

if TYPE_CHECKING:
    from collections.abc import Sequence
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
    return None if value is None else float(parse_duration(value))


def build_parser() -> argparse.ArgumentParser:
    """Describe every verb."""
    parser = Parser(prog="sbx", description="Disposable agent sandboxes on qemu:///session.")
    parser.add_argument("--json", action="store_true", help="print JSON, errors included")
    common = Parser(add_help=False)
    common.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    verbs = parser.add_subparsers(dest="verb", required=True, parser_class=Parser)

    create_flags = Parser(add_help=False)
    create_flags.add_argument("base", choices=FLAVOURS)
    create_flags.add_argument("--name", help="sandbox name; default <base>-<6 hex>")
    create_flags.add_argument("--net", choices=NETS, default="none")
    create_flags.add_argument("--mem", help="memory such as 2G")
    create_flags.add_argument("--cpus", type=int)
    create_flags.add_argument("--ttl", help="lifetime such as 30m or 2h")

    verbs.add_parser("create", parents=[common, create_flags], help="start a sandbox")

    run = verbs.add_parser(
        "run", parents=[common, create_flags], help="create, copy in, exec, copy out, destroy"
    )
    run.add_argument("--in", dest="inputs", action="append", default=[], metavar="PATH")
    run.add_argument("--out", dest="outputs", action="append", default=[], metavar="GUEST_PATH")
    run.add_argument("--to", help="host directory for --out")
    run.add_argument("--timeout", help="command timeout such as 10m")

    execute = verbs.add_parser("exec", parents=[common], help="run a command in a sandbox")
    execute.add_argument("name")
    execute.add_argument("--timeout", help="command timeout such as 10m")
    execute.add_argument("--agent", action="store_true", help="use qemu-ga guest-exec, not SSH")

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

    gc = verbs.add_parser("gc", parents=[common], help="remove expired and orphaned sandboxes")
    gc.add_argument("--dry-run", action="store_true")

    base = verbs.add_parser("base", parents=[common], help="list or build bases")
    base_verbs = base.add_subparsers(dest="base_verb", required=True, parser_class=Parser)
    base_verbs.add_parser("list", parents=[common])
    build = base_verbs.add_parser("build", parents=[common])
    build.add_argument("flavour", choices=FLAVOURS)
    build.add_argument("--flake", help="flake reference; default the configured checkout")
    return parser


def _request(sandboxes: Sandboxes, args: argparse.Namespace) -> Request:
    return sandboxes.request(
        args.base, name=args.name, net=args.net, memory=args.mem, cpus=args.cpus, ttl=args.ttl
    )


def _print_exec(result: ExecResult) -> int:
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    if result.truncated:
        print("sbx: output truncated", file=sys.stderr)
    if result.timed_out:
        print("sbx: the command timed out", file=sys.stderr)
        return 124
    return 255 if result.exit_code is None else result.exit_code


def _run(sandboxes: Sandboxes, args: argparse.Namespace, *, as_json: bool) -> tuple[object, int]:
    command = _command(args)
    if args.outputs and args.to is None:
        msg = "--out needs --to"
        raise SbxError(msg, code="usage")
    created = sandboxes.create(_request(sandboxes, args))
    name = str(created["name"])
    try:
        copied_in = [sandboxes.copy(path, f"{name}:/root/") for path in args.inputs]
        timeout = _timeout(args.timeout)
        if as_json:
            result = sandboxes.exec_capture(name, command, timeout=timeout, agent=False)
            code = 0
        else:
            code = sandboxes.exec_attached(name, command, timeout=timeout)
            result = None
        copied_out = [sandboxes.copy(f"{name}:{path}", args.to) for path in args.outputs]
    finally:
        sandboxes.destroy(name)
    if not as_json:
        return None, code
    payload = {
        "sandbox": created,
        "in": copied_in,
        "exec": None if result is None else result.as_json(),
        "out": copied_out,
    }
    return payload, code


def dispatch(  # noqa: C901, PLR0911, PLR0912
    sandboxes: Sandboxes, args: argparse.Namespace, *, as_json: bool
) -> tuple[object, int]:
    """Run one verb and return its result and exit code."""
    match args.verb:
        case "create":
            return sandboxes.create(_request(sandboxes, args)), 0
        case "run":
            return _run(sandboxes, args, as_json=as_json)
        case "exec":
            command = _command(args)
            timeout = _timeout(args.timeout)
            if as_json or args.agent:
                result = sandboxes.exec_capture(
                    args.name, command, timeout=timeout, agent=args.agent
                )
                if as_json:
                    return result.as_json(), 0
                return None, _print_exec(result)
            return None, sandboxes.exec_attached(args.name, command, timeout=timeout)
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
        case "gc":
            return sandboxes.gc(dry_run=args.dry_run), 0
        case "base":
            if args.base_verb == "list":
                return sandboxes.base_list(), 0
            return sandboxes.base_build(args.flavour, args.flake), 0
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
    leading, command = split_command(sys.argv[1:] if argv is None else argv)
    as_json = "--json" in leading
    try:
        args = build_parser().parse_args(leading)
        args.command = command
        settings = Settings.load(settings_path)

        def connect(require_slice: bool) -> Backend:  # noqa: FBT001
            from sbx.backend import LibvirtBackend  # noqa: PLC0415

            return LibvirtBackend(settings, require_slice=require_slice)

        sandboxes = Sandboxes(settings, Paths.from_environment(), connect, caller_session())
        result, code = dispatch(sandboxes, args, as_json=as_json)
    except (SbxError, OSError) as error:
        code = error.code if isinstance(error, SbxError) else "os-error"
        journal.record(f"failed: {error}", code=code)
        if as_json:
            print(json.dumps({"error": {"code": code, "message": str(error)}}))
        else:
            print(f"sbx: {error}", file=sys.stderr)
        return USAGE_EXIT if code == "usage" else 1
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        _plain(result)
    return code
