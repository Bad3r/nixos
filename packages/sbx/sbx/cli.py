# Copyright (c) 2026 Bad3r
"""Command line of sbx, built from the operation registry."""

import argparse
import json
import os
import sys
from typing import TYPE_CHECKING, NoReturn, cast

from sbx import completion, ops
from sbx.config import Settings, caller_session
from sbx.errors import SbxError
from sbx.model import ExecResult
from sbx.pipeline import RunResult
from sbx.results import FocusResult, WindowsResult
from sbx.sandboxes import open_sandboxes

if TYPE_CHECKING:
    from collections.abc import Sequence
    from pathlib import Path

    from sbx.results import Result, Window
    from sbx.sandboxes import Sandboxes

USAGE_EXIT = 2


class Parser(argparse.ArgumentParser):
    """Raise usage errors so --json can report them."""

    def error(self, message: str) -> NoReturn:
        """Turn an argparse failure into an SbxError."""
        msg = f"{self.prog}: {message}"
        raise SbxError(msg, code="usage")


def _help(param: ops.Param, settings: Settings | None) -> str | None:
    if settings is None or param.limits is None:
        return param.help
    return f"{param.help}; {param.limits(settings)}"


def _arguments(
    parser: argparse.ArgumentParser, operation: ops.Operation, settings: Settings | None
) -> None:
    exclusive = parser.add_mutually_exclusive_group(required=True) if operation.one_of else None
    for param in operation.params:
        # The guest command follows --, which split_command takes off first.
        if not param.cli or param.kind == "command":
            continue
        target = exclusive if exclusive is not None and param.name in operation.one_of else parser
        choices = param.enum or None
        help_text = _help(param, settings)
        if param.flag is None:
            if param.repeatable:
                nargs = "+" if param.required else "*"
            else:
                nargs = None if param.required else "?"
            target.add_argument(
                param.name, nargs=nargs, choices=choices, metavar=param.metavar, help=help_text
            )
        elif param.kind == "boolean":
            target.add_argument(param.flag, dest=param.name, action="store_true", help=help_text)
        elif param.kind == "integer":
            target.add_argument(
                param.flag, dest=param.name, type=int, metavar=param.metavar, help=help_text
            )
        elif param.repeatable or param.kind == "env":
            target.add_argument(
                param.flag,
                dest=param.name,
                action="append",
                default=[],
                metavar=param.metavar,
                help=help_text,
            )
        else:
            target.add_argument(
                param.flag,
                dest=param.name,
                choices=choices,
                default=param.default,
                metavar=param.metavar,
                help=help_text,
            )


def build_parser(settings: Settings | None = None) -> argparse.ArgumentParser:
    """Describe every verb of the registry; `settings` add the host's defaults and ceilings."""
    parser = Parser(prog="sbx", description="Disposable agent sandboxes on qemu:///session.")
    parser.add_argument("--json", action="store_true", help="print JSON, errors included")
    common = Parser(add_help=False)
    common.add_argument(
        "--json", action="store_true", default=argparse.SUPPRESS, help="print JSON, errors included"
    )
    verbs = parser.add_subparsers(dest="verb", required=True, parser_class=Parser)
    for group, operations in ops.grouped():
        target = verbs
        if group:
            (name,) = group
            holder = verbs.add_parser(name, help=ops.GROUPS[name])
            target = holder.add_subparsers(dest=f"{name}_verb", required=True, parser_class=Parser)
        for operation in operations:
            parents = [common] if operation.takes_json else []
            example = operation.example
            leaf = target.add_parser(
                operation.path[-1],
                parents=parents,
                help=operation.help,
                description=operation.help,
                usage=operation.usage,
                epilog=None if example is None else f"example:\n  {example}",
                formatter_class=argparse.RawDescriptionHelpFormatter,
            )
            leaf.set_defaults(operation=operation)
            _arguments(leaf, operation, settings)
    return parser


def split_command(arguments: Sequence[str]) -> tuple[list[str], list[str]]:
    """Separate sbx's own arguments from the guest command after the first --."""
    arguments = list(arguments)
    if "--" not in arguments:
        return arguments, []
    split = arguments.index("--")
    return arguments[:split], arguments[split + 1 :]


def parse(
    arguments: Sequence[str], parser: argparse.ArgumentParser | None = None
) -> tuple[ops.Operation, ops.Args]:
    """Return the operation a command line names and its arguments."""
    leading, command = split_command(arguments)
    namespace = (parser or build_parser()).parse_args(leading)
    operation = cast("ops.Operation", namespace.operation)
    values: dict[str, object] = {
        param.name: getattr(namespace, param.name)
        for param in operation.params
        if param.cli and param.kind != "command"
    }
    if operation.param("command") is not None:
        values["command"] = command
    return operation, ops.Args(operation, values)


def _print_exec(result: ExecResult) -> None:
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    if result.truncated:
        print("sbx: output truncated", file=sys.stderr)
    if result.timed_out:
        print("sbx: the command timed out", file=sys.stderr)
    if result.transport_error is not None:
        print(f"sbx: {result.transport_error}", file=sys.stderr)


def _print_run(result: RunResult) -> None:
    if result.execution is not None:
        _print_exec(result.execution)
    for entry in result.failed_outputs():
        print(f"sbx: copy out of {entry.source} failed: {entry.failure}", file=sys.stderr)
    if result.cleanup_error is not None:
        print(f"sbx: cleanup failed: {result.cleanup_error}", file=sys.stderr)


def _plain(document: object) -> None:
    if document is None:
        return
    if isinstance(document, list):
        for item in cast("list[object]", document):
            _plain(item)
        return
    if isinstance(document, dict):
        fields = cast("dict[str, object]", document)
        print(" ".join(f"{key}={value}" for key, value in fields.items() if value is not None))
        return
    print(document)


def _print_window(window: Window) -> None:
    print(
        f"id={window.id} x={window.x} y={window.y} width={window.width} "
        f"height={window.height} name={json.dumps(window.name)}"
    )


def _print(result: Result) -> None:
    if isinstance(result, ExecResult):
        _print_exec(result)
    elif isinstance(result, RunResult):
        _print_run(result)
    elif isinstance(result, WindowsResult):
        for window in result.windows:
            _print_window(window)
    elif isinstance(result, FocusResult):
        _print_window(result.window)
    else:
        _plain(result.as_json())


def render(outcome: Result | ops.Failure, *, as_json: bool) -> int:
    """Print an outcome and return the exit code."""
    if isinstance(outcome, ops.Failure):
        if as_json:
            print(json.dumps(outcome.as_json()))
        else:
            if outcome.partial is not None:
                _print(outcome.partial)
            print(f"sbx: {outcome.error}", file=sys.stderr)
        return USAGE_EXIT if outcome.code == "usage" else 1
    if as_json:
        print(json.dumps(outcome.as_json(), indent=2))
    else:
        _print(outcome)
    return outcome.exit_status()


def _help_settings(path: Path) -> Settings | None:
    """Return the settings for help text; a verb loads them again and reports what fails."""
    try:
        return Settings.load(path)
    except OSError, ValueError, KeyError, TypeError, SbxError:
        return None


def main(settings_path: Path, argv: Sequence[str] | None = None) -> int:
    """Parse, run, print; failures exit non-zero, as JSON under --json."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    # Completion and the bare help show no defaults, so they never read the settings.
    completing = "_ARGCOMPLETE" in os.environ
    settings = None if completing or not arguments else _help_settings(settings_path)
    parser = build_parser(settings)
    completion.autocomplete(parser, settings_path)
    if not arguments:
        parser.print_help()
        return 0
    as_json = "--json" in split_command(arguments)[0]
    try:
        operation, args = parse(arguments, parser)
    except SbxError as error:
        return render(ops.fail(error), as_json=as_json)
    ctx = ops.Ctx(session=caller_session(), stdio_attached=not as_json)

    def connect(session: str | None) -> Sandboxes:
        return open_sandboxes(settings or Settings.load(settings_path), session)

    return render(ops.invoke(operation, connect, args, ctx), as_json=as_json)
