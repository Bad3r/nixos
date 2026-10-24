# Copyright (c) 2026 Bad3r
"""Command line of the workloads app."""

import argparse
import json
import shutil
import subprocess
import sys
from typing import TYPE_CHECKING, NoReturn, cast

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence
    from pathlib import Path

USAGE_EXIT = 2

type Record = dict[str, object]
# Runs `sbx list --json` and returns its exit code and output, or None without sbx.
type SbxRunner = Callable[[], tuple[int, str] | None]


class WorkloadsError(Exception):
    """A failure the command line reports with a code."""

    def __init__(self, message: str, *, code: str) -> None:
        """Keep the code next to the message."""
        super().__init__(message)
        self.code = code


class Parser(argparse.ArgumentParser):
    """Raise usage errors so --json can report them."""

    def error(self, message: str) -> NoReturn:
        """Turn an argparse failure into a WorkloadsError."""
        msg = f"{self.prog}: {message}"
        raise WorkloadsError(msg, code="usage")


def build_parser() -> argparse.ArgumentParser:
    """Describe every verb."""
    parser = Parser(prog="workloads", description="Declared workloads and live sandboxes.")
    parser.add_argument("--json", action="store_true", help="print JSON, errors included")
    common = Parser(add_help=False)
    common.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    verbs = parser.add_subparsers(dest="verb", required=True, parser_class=Parser)
    verbs.add_parser(
        "names", parents=[common], help="list declared names, resolver records, and sandboxes"
    )
    return parser


def run_sbx() -> tuple[int, str] | None:
    """Run `sbx list --json` from PATH, or return None when sbx is not installed."""
    sbx = shutil.which("sbx")
    if sbx is None:
        return None
    result = subprocess.run([sbx, "list", "--json"], capture_output=True, text=True, check=False)
    return result.returncode, result.stdout or result.stderr


def sandboxes(runner: SbxRunner) -> list[Record] | None:
    """Return live sandboxes as names, or None when sbx is not installed."""
    result = runner()
    if result is None:
        return None
    code, output = result
    try:
        parsed: object = json.loads(output)
    except json.JSONDecodeError:
        parsed = None
    if code != 0 or not isinstance(parsed, list):
        message: object = output.strip()
        if isinstance(parsed, dict):
            error = cast("Record", parsed).get("error")
            if isinstance(error, dict):
                message = cast("Record", error).get("message", message)
        msg = f"sbx list failed: {message}"
        raise WorkloadsError(msg, code="sbx")
    return [
        {
            "name": sandbox["domain"],
            "kind": "sandbox",
            "address": sandbox.get("address"),
            "network": sandbox.get("net"),
            "state": sandbox.get("state"),
        }
        for sandbox in cast("list[Record]", parsed)
    ]


def load_names(path: Path) -> Record:
    """Read the names file the workloads module writes."""
    try:
        declared: object = json.loads(path.read_text())
    except FileNotFoundError as error:
        msg = f"{path} is missing; no workload declares a name on this host"
        raise WorkloadsError(msg, code="no-names") from error
    if not isinstance(declared, dict):
        msg = f"{path} holds no JSON object"
        raise WorkloadsError(msg, code="names-file")
    return cast("Record", declared)


def names(declared: Record, runner: SbxRunner) -> Record:
    """Combine declared names, per-network resolver records, and live sandboxes."""
    entries = cast("dict[str, Record]", declared.get("names", {}))
    return {
        "names": [{"name": name, **entry} for name, entry in sorted(entries.items())],
        "resolvers": declared.get("networks", {}),
        "sandboxes": sandboxes(runner),
    }


def _table(rows: list[list[str]]) -> None:
    widths = [max(len(row[column]) for row in rows) for column in range(len(rows[0]) - 1)]
    for row in rows:
        cells = [cell.ljust(width) for cell, width in zip(row, widths, strict=False)]
        print("  ".join([*cells, row[-1]]))


def _plain(report: Record) -> None:
    live = cast("list[Record] | None", report["sandboxes"])
    rows = [["NAME", "KIND", "ADDRESS", "NETWORK"]] + [
        [str(entry.get(field) or "-") for field in ("name", "kind", "address", "network")]
        for entry in cast("list[Record]", report["names"]) + (live or [])
    ]
    _table(rows)
    resolvers = cast("dict[str, dict[str, list[str]]]", report["resolvers"])
    records = [
        [network, address, " ".join(hostnames)]
        for network, hosts in sorted(resolvers.items())
        for address, hostnames in sorted(hosts.items())
    ]
    if records:
        print()
        _table([["NETWORK", "ADDRESS", "HOSTNAMES"], *records])


def main(names_path: Path, argv: Sequence[str] | None = None, runner: SbxRunner = run_sbx) -> int:
    """Parse, run, print; failures exit non-zero, as JSON under --json."""
    arguments = sys.argv[1:] if argv is None else list(argv)
    as_json = "--json" in arguments
    try:
        build_parser().parse_args(arguments)
        report = names(load_names(names_path), runner)
    except (WorkloadsError, OSError) as error:
        code = error.code if isinstance(error, WorkloadsError) else "os-error"
        if as_json:
            print(json.dumps({"error": {"code": code, "message": str(error)}}))
        else:
            print(f"workloads: {error}", file=sys.stderr)
        return USAGE_EXIT if code == "usage" else 1
    if report["sandboxes"] is None:
        print("workloads: sbx is not installed, so no sandbox is listed", file=sys.stderr)
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        _plain(report)
    return 0
