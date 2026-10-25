# Copyright (c) 2026 Bad3r
"""Command line of the workloads app."""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
from typing import TYPE_CHECKING, NoReturn, cast

from workloads.grants import (
    GUEST_PATTERN,
    SANDBOX_PATTERN,
    GrantError,
    format_duration,
    parse_duration,
)

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence
    from pathlib import Path

USAGE_EXIT = 2
GRANT_SOCKET = "/run/workloads/grant.sock"
DEFAULT_TTL = "30m"
TTL_TEXT = (
    "A grant permits all traffic on its path, established connections included, only until"
    " its TTL ends. When it expires or is revoked, every connection it admitted stops at once;"
    " connections of other grants keep working."
)
SESSION_VARIABLES = (("CLAUDE_CODE_SESSION_ID", "claude"), ("CODEX_THREAD_ID", "codex"))
SHARE_TEXT = (
    "A guest takes the shares its declaration marks runtime = true; a sandbox takes its shared"
    " directory read-write, or a workloads.grants.sandboxShares entry read-only. A share stays"
    " until detached or the guest stops, managed saves included."
)

type Record = dict[str, object]
# Runs sbx with the arguments and returns its exit code and output, or None without sbx.
type SbxRunner = Callable[[Sequence[str]], tuple[int, str] | None]
# Sends one request to workload-grantd and returns its answer.
type Helper = Callable[[Record], Record]


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
    grant = verbs.add_parser(
        "grant",
        parents=[common],
        help="open a path from a guest or sandbox to a target",
        description=TTL_TEXT,
    )
    grant.add_argument("source", help="sbx-<name>, guest:<name>, or a guest name")
    grant.add_argument(
        "target", help="host:<service>, guest:<name>, or service:<name>[:port[/udp]]"
    )
    grant.add_argument(
        "--ttl",
        default=DEFAULT_TTL,
        help=f"lifetime such as 30m or 2h; all of the grant's traffic stops then ({DEFAULT_TTL})",
    )
    revoke = verbs.add_parser(
        "revoke",
        parents=[common],
        help="end grants; their connections stop at once",
        description=(
            "End grants now. Every connection of a revoked grant stops at once, established"
            " ones included; connections of other grants keep working."
        ),
    )
    chosen = revoke.add_mutually_exclusive_group(required=True)
    chosen.add_argument("id", nargs="?", help="grant id")
    chosen.add_argument("--all", metavar="SOURCE", dest="source", help="every grant of a source")
    verbs.add_parser("grants", parents=[common], help="list live grants")
    # No --json between share and its verb, so permission rules see one spelling.
    share = verbs.add_parser("share", help="attach or detach a runtime share")
    share_verbs = share.add_subparsers(dest="share_verb", required=True, parser_class=Parser)
    for verb, text in (
        ("attach", "hot-plug a share into a running guest or sandbox"),
        ("detach", "remove a share; fails while the guest still holds it"),
    ):
        action = share_verbs.add_parser(verb, parents=[common], help=text, description=SHARE_TEXT)
        action.add_argument("target", help="sbx-<name>, guest:<name>, or a guest name")
        action.add_argument("share", help="a guest's runtime share, or shared or a sandbox share")
    return parser


def run_sbx(arguments: Sequence[str]) -> tuple[int, str] | None:
    """Run sbx from PATH, or return None when sbx is not installed."""
    sbx = shutil.which("sbx")
    if sbx is None:
        return None
    result = subprocess.run([sbx, *arguments], capture_output=True, text=True, check=False)
    return result.returncode, result.stdout or result.stderr


def _sbx_json(runner: SbxRunner, arguments: Sequence[str]) -> object | None:
    """Parse sbx's JSON output, or return None when sbx is not installed."""
    result = runner(arguments)
    if result is None:
        return None
    code, output = result
    try:
        parsed: object = json.loads(output)
    except json.JSONDecodeError:
        parsed = None
    if code != 0 or parsed is None or (isinstance(parsed, dict) and "error" in parsed):
        message: object = output.strip()
        if isinstance(parsed, dict):
            error = cast("Record", parsed).get("error")
            if isinstance(error, dict):
                message = cast("Record", error).get("message", message)
        msg = f"sbx {arguments[0]} failed: {message}"
        raise WorkloadsError(msg, code="sbx")
    return cast("object", parsed)


def sandboxes(runner: SbxRunner) -> list[Record] | None:
    """Return live sandboxes as names, or None when sbx is not installed."""
    parsed = _sbx_json(runner, ["list", "--json"])
    if parsed is None:
        return None
    if not isinstance(parsed, list):
        msg = "sbx list printed no list"
        raise WorkloadsError(msg, code="sbx")
    try:
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
    except (AttributeError, KeyError, TypeError) as error:
        msg = f"sbx list printed a malformed sandbox: {error!r}"
        raise WorkloadsError(msg, code="sbx") from error


def load_names(path: Path) -> Record:
    """Read the names file the workloads module writes."""
    try:
        declared: object = json.loads(path.read_text())
    except FileNotFoundError as error:
        msg = f"{path} is missing; the workloads app module installs it with the command"
        raise WorkloadsError(msg, code="no-names") from error
    except ValueError as error:
        msg = f"{path} holds no valid JSON: {error}"
        raise WorkloadsError(msg, code="names-file") from error
    if not isinstance(declared, dict):
        msg = f"{path} holds no JSON object"
        raise WorkloadsError(msg, code="names-file")
    return cast("Record", declared)


def _hostnames(value: object) -> list[str]:
    if not isinstance(value, list):
        msg = f"hostnames {value!r} are no list"
        raise TypeError(msg)
    return [str(hostname) for hostname in cast("list[object]", value)]


def names(declared: Record, runner: SbxRunner) -> Record:
    """Combine declared names, per-network resolver records, and live sandboxes."""
    try:
        entries = cast("dict[str, Record]", declared["names"])
        listed = [{"name": name, **entry} for name, entry in sorted(entries.items())]
        networks = cast("dict[str, dict[str, object]]", declared["networks"])
        resolvers = {
            network: {address: _hostnames(value) for address, value in hosts.items()}
            for network, hosts in networks.items()
        }
    except (AttributeError, KeyError, TypeError) as error:
        msg = f"the names file is malformed: {error!r}"
        raise WorkloadsError(msg, code="names-file") from error
    return {"names": listed, "resolvers": resolvers, "sandboxes": sandboxes(runner)}


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


def ask_helper(request: Record) -> Record:
    """Send one request to workload-grantd over its socket."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        # A detach waits for the guest to release the device.
        connection.settimeout(45)
        try:
            connection.connect(GRANT_SOCKET)
        except FileNotFoundError as error:
            msg = f"{GRANT_SOCKET} is missing; no grant rule or present guest is declared"
            raise WorkloadsError(msg, code="no-helper") from error
        connection.sendall(json.dumps(request).encode())
        connection.shutdown(socket.SHUT_WR)
        chunks: list[bytes] = []
        while chunk := connection.recv(65536):
            chunks.append(chunk)
    try:
        answer: object = json.loads(b"".join(chunks))
    except ValueError as error:
        msg = f"workload-grantd answered no JSON: {error}"
        raise WorkloadsError(msg, code="helper") from error
    if not isinstance(answer, dict):
        msg = "workload-grantd answered no JSON object"
        raise WorkloadsError(msg, code="helper")
    return cast("Record", answer)


def caller_session() -> str | None:
    """Return the agent session that runs the command, if any."""
    for variable, client in SESSION_VARIABLES:
        value = os.environ.get(variable)
        if value:
            return f"{client}:{value}"
    return None


def canonical_source(source: str, role: str = "source") -> str:
    """`sbx-<name>` or `guest:<name>`; a bare name is a guest."""
    if SANDBOX_PATTERN.fullmatch(source):
        return source
    canonical = source if source.startswith("guest:") else f"guest:{source}"
    if GUEST_PATTERN.fullmatch(canonical) is None:
        msg = f"'{source}' is no {role}: expected sbx-<name>, guest:<name>, or a guest name"
        raise WorkloadsError(msg, code=f"invalid-{role}")
    return canonical


def grant_source(source: str, runner: SbxRunner) -> tuple[str, str | None]:
    """Canonical source and, for a sandbox, its address from `sbx info`."""
    canonical = canonical_source(source)
    if not SANDBOX_PATTERN.fullmatch(canonical):
        return canonical, None
    info = _sbx_json(runner, ["info", canonical.removeprefix("sbx-"), "--json"])
    if info is None:
        msg = f"{canonical} is a sandbox, and sbx is not installed"
        raise WorkloadsError(msg, code="sbx")
    address = cast("Record", info).get("address") if isinstance(info, dict) else None
    if not isinstance(address, str):
        msg = f"{canonical} has no address on a workload network"
        raise WorkloadsError(msg, code="no-address")
    return canonical, address


def revoke_request(source: str, runner: SbxRunner) -> Record:
    """Revoke by name, and by address while sbx still knows the sandbox."""
    canonical = canonical_source(source)
    request: Record = {"verb": "revoke", "source": canonical}
    if not SANDBOX_PATTERN.fullmatch(canonical):
        return request
    result = runner(["info", canonical.removeprefix("sbx-"), "--json"])
    if result is None:
        return request
    code, output = result
    try:
        info: object = json.loads(output)
    except json.JSONDecodeError:
        info = None
    details = cast("Record", info) if isinstance(info, dict) else {}
    error = details.get("error")
    if code != 0 or error is not None:
        if isinstance(error, dict) and cast("Record", error).get("code") == "not-found":
            # A destroyed sandbox is revoked by the name its grants carry.
            return request
        msg = f"sbx info failed: {output.strip()}"
        raise WorkloadsError(msg, code="sbx")
    if isinstance(details.get("address"), str):
        request["address"] = details["address"]
    return request


def share_sandbox(verb: str, sandbox: str, tag: str, runner: SbxRunner) -> Record:
    """Run `sbx share`, keeping the code of a refusal."""
    result = runner(["share", verb, sandbox.removeprefix("sbx-"), tag, "--json"])
    if result is None:
        msg = f"{sandbox} is a sandbox, and sbx is not installed"
        raise WorkloadsError(msg, code="sbx")
    code, output = result
    try:
        parsed: object = json.loads(output)
    except json.JSONDecodeError:
        parsed = None
    details = cast("Record", parsed) if isinstance(parsed, dict) else {}
    error = details.get("error")
    if isinstance(error, dict):
        failure = cast("Record", error)
        raise WorkloadsError(str(failure.get("message")), code=str(failure.get("code")))
    if code != 0 or not details:
        msg = f"sbx share {verb} failed: {output.strip()}"
        raise WorkloadsError(msg, code="sbx")
    return details


def share(verb: str, target: str, tag: str, runner: SbxRunner, helper: Helper) -> Record:
    """Attach or detach a share; sandboxes go through sbx, guests through the helper."""
    canonical = canonical_source(target, "target")
    if SANDBOX_PATTERN.fullmatch(canonical):
        details = share_sandbox(verb, canonical, tag, runner)
        fields, source = ("tag", "read_only", "attached", "host_path"), "sbx"
    else:
        request: Record = {
            "verb": f"share-{verb}",
            "guest": canonical.removeprefix("guest:"),
            "share": tag,
        }
        details = cast("Record", _ask(helper, request)["share"])
        fields, source = ("tag", "read_only", "attached", "mount_point"), "helper"
    missing = [field for field in fields if field not in details]
    if missing:
        msg = f"the {source} answer lacks {', '.join(missing)}"
        raise WorkloadsError(msg, code=source)
    return {"share": {"target": canonical} | {field: details[field] for field in fields}}


def _ask(helper: Helper, request: Record) -> Record:
    session = caller_session()
    answer = helper(request | ({"session": session} if session else {}))
    error = answer.get("error")
    if isinstance(error, dict):
        details = cast("Record", error)
        raise WorkloadsError(str(details.get("message")), code=str(details.get("code")))
    return answer


def dispatch(
    arguments: argparse.Namespace, names_path: Path, runner: SbxRunner, helper: Helper
) -> Record:
    """Run one verb and return its JSON result."""
    try:
        match arguments.verb:
            case "names":
                return names(load_names(names_path), runner)
            case "grant":
                source, address = grant_source(arguments.source, runner)
                request: Record = {
                    "verb": "grant",
                    "source": source,
                    "target": arguments.target,
                    "ttl": parse_duration(arguments.ttl),
                }
                if address is not None:
                    request["address"] = address
                return _ask(helper, request)
            case "revoke":
                if arguments.id is not None:
                    return _ask(helper, {"verb": "revoke", "id": arguments.id})
                return _ask(helper, revoke_request(arguments.source, runner))
            case "share":
                return share(
                    arguments.share_verb, arguments.target, arguments.share, runner, helper
                )
            case _:
                return _ask(helper, {"verb": "list"})
    except GrantError as error:
        raise WorkloadsError(str(error), code=error.code) from error


def _plain_grant(grant: Record) -> None:
    expires = format_duration(cast("int", grant["expires_in"]))
    print(f"{grant['id']}  {grant['source']} -> {grant['target']}  expires in {expires}")


def _plain_share(details: Record) -> None:
    tag, target = details["tag"], details["target"]
    if not details["attached"]:
        print(f"detached {tag} from {target}")
        return
    mode = "read-only" if details["read_only"] else "read-write"
    print(f"attached {tag} to {target}, {mode}")
    if details.get("mount_point"):
        print(f"mount it in the guest with: mount {details['mount_point']}")


def _print(verb: str, result: Record) -> None:
    match verb:
        case "names":
            if result["sandboxes"] is None:
                print("workloads: sbx is not installed, so no sandbox is listed", file=sys.stderr)
            _plain(result)
        case "grant":
            _plain_grant(cast("Record", result["grant"]))
        case "revoke":
            revoked = cast("list[str]", result["revoked"])
            print(f"revoked {', '.join(revoked)}" if revoked else "no live grant matched")
        case "share":
            _plain_share(cast("Record", result["share"]))
        case _:
            grants = cast("list[Record]", result["grants"])
            rows = [
                [
                    str(grant["id"]),
                    str(grant["source"]),
                    str(grant["target"]),
                    format_duration(cast("int", grant["expires_in"])),
                ]
                for grant in grants
            ]
            if rows:
                _table([["ID", "SOURCE", "TARGET", "EXPIRES IN"], *rows])
            else:
                print("no live grant")


def main(
    names_path: Path,
    argv: Sequence[str] | None = None,
    runner: SbxRunner = run_sbx,
    helper: Helper = ask_helper,
) -> int:
    """Parse, run, print; failures exit non-zero, as JSON under --json."""
    arguments = sys.argv[1:] if argv is None else list(argv)
    as_json = "--json" in arguments
    try:
        parsed = build_parser().parse_args(arguments)
        result = dispatch(parsed, names_path, runner, helper)
    except (WorkloadsError, OSError) as error:
        code = error.code if isinstance(error, WorkloadsError) else "os-error"
        if as_json:
            print(json.dumps({"error": {"code": code, "message": str(error)}}))
        else:
            print(f"workloads: {error}", file=sys.stderr)
        return USAGE_EXIT if code == "usage" else 1
    if as_json:
        if parsed.verb == "names" and result["sandboxes"] is None:
            print("workloads: sbx is not installed, so no sandbox is listed", file=sys.stderr)
        print(json.dumps(result, indent=2))
    else:
        _print(parsed.verb, result)
    return 0
