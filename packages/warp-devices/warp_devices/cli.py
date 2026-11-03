# Copyright (c) 2026 Bad3r
"""Command line of the warp-devices app."""

import argparse
import json
import os
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING, NoReturn

from warp_devices import devices, history
from warp_devices.api import ApiError, Client, Getter
from warp_devices.render import Row, printable, table, use_color
from warp_devices.timefmt import ago, local_clock, span

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

USAGE_EXIT = 2
LOOKUP_EXIT = 3
BROKEN_PIPE_EXIT = 141
INTERRUPT_EXIT = 130
FORBIDDEN = 403
COMMANDS = ("list", "history")
VALUE_FLAGS = ("--account-id-file", "--token-file", "--hours")
CREDENTIAL_PATTERN = re.compile(r"[\x21-\x7e]+")
CREDENTIAL_SOURCE = (
    "the warp-devices app renders it from the zero_trust_read_api_token and account_id keys"
    " of secrets/cloudflare-warp.yaml"
)
PERMISSION_HINT = "the token needs the Zero Trust Read and DEX Read account permissions"


class CredentialError(Exception):
    """A credential file is missing, unreadable, or empty."""


class Parser(argparse.ArgumentParser):
    """Exit with the usage code on a bad argument."""

    def error(self, message: str) -> NoReturn:
        """Print usage and the problem, then exit 2."""
        self.print_usage(sys.stderr)
        self.exit(USAGE_EXIT, f"{self.prog}: error: {message}\n")


def config_dir() -> Path:
    """Return the directory the app's Home Manager module writes the credentials to."""
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "warp-devices"


def read_credential(path: Path) -> str:
    """Return a credential file's content without surrounding whitespace."""
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError as error:
        msg = f"cannot read {path}: {error.strerror or error}; {CREDENTIAL_SOURCE}"
        raise CredentialError(msg) from None
    except UnicodeDecodeError:
        msg = f"{path} is not UTF-8 text; {CREDENTIAL_SOURCE}"
        raise CredentialError(msg) from None
    if not value:
        msg = f"{path} is empty; {CREDENTIAL_SOURCE}"
        raise CredentialError(msg)
    # The value never reaches the message: a malformed token is still a secret.
    if not CREDENTIAL_PATTERN.fullmatch(value):
        msg = f"{path} holds more than one printable token (whitespace or control characters)"
        raise CredentialError(msg)
    return value


def hours(value: str) -> int:
    """Parse --hours within the DEX raw retention."""
    try:
        number = int(value)
    except ValueError:
        msg = f"invalid hour count {value!r}"
        raise argparse.ArgumentTypeError(msg) from None
    if not history.MIN_HOURS <= number <= history.MAX_HOURS:
        msg = f"must be {history.MIN_HOURS} to {history.MAX_HOURS}; DEX keeps raw reports 7 days"
        raise argparse.ArgumentTypeError(msg)
    return number


def build_parser() -> Parser:
    """Return the argument parser."""
    shared = Parser(add_help=False)
    shared.add_argument("--json", action="store_true", help="print JSON instead of a table")
    color = shared.add_mutually_exclusive_group()
    color.add_argument(
        "--color", dest="color", action="store_true", default=None, help="always color the table"
    )
    color.add_argument("--no-color", dest="color", action="store_false", help="never color")
    shared.add_argument("--account-id-file", type=Path, metavar="PATH")
    shared.add_argument("--token-file", type=Path, metavar="PATH")

    parser = Parser(
        prog="warp-devices",
        description="List Cloudflare Zero Trust WARP devices, or one device's recent history.",
        epilog=(
            "Without a command, runs list. Color is on for a terminal unless NO_COLOR holds a"
            " non-empty value."
        ),
    )
    commands = parser.add_subparsers(dest="command", parser_class=Parser)
    listing = commands.add_parser(
        "list",
        parents=[shared],
        help="list devices with status, Mesh and public IPs, and last seen",
        description=(
            "List active WARP registrations. STATUS is the newest DEX report of the past hour;"
            " offline means no report in that hour, unknown that DEX could not be read."
        ),
    )
    listing.add_argument("--ipv6", action="store_true", help="add the Mesh IPv6 column")
    listing.add_argument("--user", action="store_true", help="add the enrolled user column")
    past = commands.add_parser(
        "history",
        parents=[shared],
        help="show one device's status, edge, and network changes",
        description=(
            "Show a device's DEX reports: the first, the last, and every report whose status,"
            " colo, ISP, LAN, or gateway address changed or that follows a gap over five minutes."
        ),
    )
    past.add_argument("device", help="device name (case-insensitive) or device ID")
    past.add_argument(
        "--hours",
        type=hours,
        default=history.DEFAULT_HOURS,
        help=(
            f"how far back to look, {history.MIN_HOURS} to {history.MAX_HOURS}"
            f" (default {history.DEFAULT_HOURS})"
        ),
    )
    past.add_argument("--all", action="store_true", help="print every report")
    return parser


def _takes_value(arg: str) -> bool:
    """Tell whether a flag consumes the next argument, abbreviations included."""
    return len(arg) > len("--") and any(flag.startswith(arg) for flag in VALUE_FLAGS)


def with_default_command(argv: Sequence[str]) -> list[str]:
    """Move a command that follows flags to the front, or run list when none is named."""
    args = list(argv)
    if args and (args[0] in COMMANDS or args[0] in {"-h", "--help"}):
        return args
    index = 0
    while index < len(args):
        arg = args[index]
        if not arg.startswith("-"):
            if arg in COMMANDS:
                return [arg, *args[:index], *args[index + 1 :]]
            break
        index += 2 if _takes_value(arg) else 1
    return ["list", *args]


def make_client(args: argparse.Namespace) -> Client:
    """Build the API client from the credential files."""
    directory = config_dir()
    account_id = read_credential(args.account_id_file or directory / "account-id")
    token = read_credential(args.token_file or directory / "api-token")
    return Client(account_id, token)


def run_list(client: Getter, args: argparse.Namespace, now: datetime) -> int:
    """Print the device table or JSON."""
    listing = devices.load(client, now)
    for warning in listing.warnings:
        print(f"warp-devices: warning: {printable(warning)}", file=sys.stderr)
    if args.json:
        payload = {
            "devices": [device.to_json() for device in listing.devices],
            "warnings": listing.warnings,
        }
        print(json.dumps(payload, indent=2))
        return 0
    header = ["NAME", "STATUS", "MESH_IPV4"]
    header += ["MESH_IPV6"] if args.ipv6 else []
    header += ["PUBLIC_IP", "OS"]
    header += ["USER"] if args.user else []
    header += ["LAST_SEEN"]
    rows: list[Row] = []
    for device in listing.devices:
        seen = device.last_seen_at
        cells: list[str | None] = [device.name, device.status, device.mesh_ipv4]
        cells += [device.mesh_ipv6] if args.ipv6 else []
        cells += [device.public_ip, device.os]
        cells += [device.user] if args.user else []
        cells += [ago(seen, now) if seen else None]
        rows.append(Row(cells, device.status))
    color = use_color(args.color, sys.stdout)
    sys.stdout.write(table(header, rows, status_column=1, color=color))
    return 0


def _measure(value: float | None, unit: str) -> str | None:
    return None if value is None else f"{value:g}{unit}"


def run_history(client: Getter, args: argparse.Namespace, now: datetime) -> int:
    """Print one device's report timeline or JSON."""
    device, reports = history.load(client, args.device, args.hours, now)
    kept = history.entries(reports, show_all=args.all)
    name = devices.field(device, "name") or args.device
    if args.json:
        payload = {
            "device": {"id": devices.field(device, "id"), "name": name},
            "hours": args.hours,
            "reports": [entry.to_json() for entry in kept],
        }
        print(json.dumps(payload, indent=2))
        return 0
    if not kept:
        print(f"{printable(name)}: no DEX reports in the past {args.hours} hours", file=sys.stderr)
        return 0
    header = ["TIME", "GAP", "STATUS", "COLO", "ISP", "LAN", "HANDSHAKE", "LOSS"]
    rows = [
        Row(
            [
                local_clock(entry.report.moment),
                span(entry.gap_seconds) if entry.gap_seconds is not None else None,
                entry.report.status,
                entry.report.colo,
                entry.report.isp_ipv4,
                entry.report.lan_ipv4,
                _measure(entry.report.handshake_ms, " ms"),
                _measure(entry.report.loss_pct, "%"),
            ],
            entry.report.status,
        )
        for entry in kept
    ]
    shown = "" if args.all else f", {len(kept)} of {len(reports)} reports shown"
    print(f"{printable(name)}: past {args.hours} hours{shown}", file=sys.stderr)
    sys.stdout.write(table(header, rows, status_column=2, color=use_color(args.color, sys.stdout)))
    return 0


def describe(error: Exception) -> str:
    """Word a failure for stderr, adding the permission hint to a 403."""
    if isinstance(error, ApiError):
        text = f"{error}; {PERMISSION_HINT}" if error.status == FORBIDDEN else str(error)
    elif isinstance(error, ValueError):
        text = f"unexpected data from Cloudflare: {error}"
    else:
        text = str(error)
    return printable(text)


def utc_now() -> datetime:
    """Return the current time."""
    return datetime.now(UTC)


def main(
    argv: Sequence[str] | None = None,
    *,
    client: Getter | None = None,
    clock: Callable[[], datetime] = utc_now,
) -> int:
    """Run the command line; tests pass a client and a clock."""
    args = build_parser().parse_args(with_default_command(sys.argv[1:] if argv is None else argv))
    try:
        api = client or make_client(args)
        run = run_history if args.command == "history" else run_list
        code = run(api, args, clock())
        # Flushed here so a closed pipe raises inside the handler, not at interpreter exit.
        sys.stdout.flush()
    except (CredentialError, ApiError, history.LookupFailedError, ValueError) as error:
        print(f"warp-devices: {describe(error)}", file=sys.stderr)
        return LOOKUP_EXIT if isinstance(error, history.LookupFailedError) else 1
    except KeyboardInterrupt:
        return INTERRUPT_EXIT
    except BrokenPipeError:
        # Point stdout at /dev/null so the interpreter's final flush cannot raise again.
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        return BROKEN_PIPE_EXIT
    return code
