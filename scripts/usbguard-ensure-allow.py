#!/usr/bin/env python3

"""Helper to append a usbguard `allow` rule for a new device within a SOPS file.

Usage examples:

    # Provide explicit fields
    EDITOR='scripts/usbguard-ensure-allow.py \\
        --id 0951:170f \\
        --name "HyperX SoloCast" \\
        --hash gtHu32Uxh2jTnIkhQkycCLdzkYqm1fHyLzyBJCZJF2k= \\
        --parent-hash yTbqZv2hoAVyAvzT1r5iqC45+9VweaiBs362Djdgi4w= \\
        --via-port 1-5.2 \\
        --interface 01:01:00 --interface 01:02:00 --interface 03:00:00' \\
      nix develop -c sops secrets/usbguard/system76.yaml

    # Or feed a line copied from `usbguard list-devices`
    EDITOR='scripts/usbguard-ensure-allow.py \\
        --from-line \"28: block id 1058:264d serial \\\"5830475838334D43\\\" name \\\"easystore 264D\\\" hash \\\"vbqGfVCQTRDBslxpW8T6eDrYOZ+pLbeSYrNTtas3uKY=\\\" parent-hash \\\"prM+Jby/bFHCn2lNjQdAMbgc6tse3xVx+hZwjOPHSdQ=\\\" via-port \\\"2-4\\\" with-interface 08:06:50 with-connect-type \\\"hotplug\\\"\"' \\
      nix develop -c sops secrets/usbguard/system76.yaml

The script is idempotent: if an identical rule already exists, it leaves the
file untouched.
"""

from __future__ import annotations

import argparse
import sys
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List


INDENT = "        "


@dataclass
class Rule:
    device_id: str
    serial: str
    name: str
    hash: str
    parent_hash: str
    via_port: str
    with_interface: str
    connect_type: str

    def render(self) -> str:
        serial_value = self.serial if self.serial is not None else ""
        return (
            f'allow id {self.device_id} serial "{serial_value}" name "{self.name}" '
            f'hash "{self.hash}" parent-hash "{self.parent_hash}" '
            f'via-port "{self.via_port}" with-interface {self.with_interface} '
            f'with-connect-type "{self.connect_type}"'
        )


def format_interfaces(interfaces: Iterable[str]) -> str:
    values = list(interfaces)
    if not values:
        raise ValueError("At least one interface must be provided via --interface.")
    if len(values) == 1:
        return values[0]
    return "{ " + " ".join(values) + " }"


USBGUARD_LINE_RE = re.compile(
    r'id (?P<id>\S+) serial "(?P<serial>[^"]*)" name "(?P<name>[^"]*)" '
    r'hash "(?P<hash>[^"]*)" parent-hash "(?P<parent>[^"]*)" '
    r'via-port "(?P<port>[^"]*)" with-interface (?P<iface>.+?) '
    r'with-connect-type "(?P<ctype>[^"]*)"'
)


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from-line",
        help="Full `usbguard list-devices` line (e.g. `28: block id ...`).",
    )
    parser.add_argument("--id", dest="device_id", help="Device USB id (vendor:product)")
    parser.add_argument("--serial", default="", help="USB serial (empty string allowed).")
    parser.add_argument("--name", help="Friendly device name.")
    parser.add_argument("--hash", help="usbguard hash for the device.")
    parser.add_argument("--parent-hash", help="usbguard parent device hash.")
    parser.add_argument("--via-port", help="Physical USB port, e.g. 1-5.2.")
    parser.add_argument(
        "--interface",
        action="append",
        dest="interfaces",
        help="Interface descriptor (repeat for multiple).",
    )
    parser.add_argument(
        "--connect-type",
        default="unknown",
        help="usbguard connect type (default: unknown).",
    )
    parser.add_argument(
        "--after",
        default=None,
        help="Insert after the first rule containing this substring (optional).",
    )
    parser.add_argument("path", nargs="?", help="Path provided by sops when used as EDITOR.")
    return parser.parse_args(argv)


def build_rule(args: argparse.Namespace) -> Rule:
    if args.from_line:
        return parse_usbguard_line(args.from_line)

    missing = [
        flag
        for flag, present in [
            ("--id", bool(args.device_id)),
            ("--name", bool(args.name)),
            ("--hash", bool(args.hash)),
            ("--parent-hash", bool(args.parent_hash)),
            ("--via-port", bool(args.via_port)),
            ("--interface", bool(args.interfaces)),
        ]
        if not present
    ]
    if missing:
        raise SystemExit("Missing required options: " + ", ".join(missing))

    with_interface = format_interfaces(args.interfaces)
    return Rule(
        device_id=args.device_id,
        serial=args.serial,
        name=args.name,
        hash=args.hash,
        parent_hash=args.parent_hash,
        via_port=args.via_port,
        with_interface=with_interface,
        connect_type=args.connect_type,
    )


def parse_usbguard_line(line: str) -> Rule:
    cleaned = line.strip()
    if cleaned and cleaned[0] == cleaned[-1] and cleaned[0] in {"'", '"'}:
        cleaned = cleaned[1:-1]
    cleaned = cleaned.strip()
    id_pos = cleaned.find("id ")
    if id_pos == -1:
        raise SystemExit("Unable to locate `id` in supplied line.")
    cleaned = cleaned[id_pos:]
    if cleaned.startswith("id "):
        searchable = cleaned
    elif cleaned.startswith("block id "):
        searchable = cleaned[len("block ") :]
    else:
        searchable = cleaned

    match = USBGUARD_LINE_RE.search(searchable)
    if not match:
        raise SystemExit("Unable to parse usbguard line; verify the format.")

    iface = match.group("iface").strip()

    return Rule(
        device_id=match.group("id"),
        serial=match.group("serial"),
        name=match.group("name"),
        hash=match.group("hash"),
        parent_hash=match.group("parent"),
        via_port=match.group("port"),
        with_interface=iface,
        connect_type=match.group("ctype"),
    )


def ensure_rule(path: Path, rule: Rule, insert_after: str | None) -> bool:
    content = path.read_text()
    lines = content.splitlines()
    formatted = f"{INDENT}{rule.render()}"

    if formatted in lines:
        return False

    insert_idx = find_insert_index(lines, insert_after)
    lines.insert(insert_idx, formatted)
    path.write_text("\n".join(lines) + "\n")
    return True


def find_insert_index(lines: List[str], insert_after: str | None) -> int:
    if insert_after:
        for idx, line in enumerate(lines):
            if insert_after in line:
                return idx + 1
    for idx in range(len(lines) - 1, -1, -1):
        if lines[idx].startswith(f"{INDENT}allow "):
            return idx + 1
    return len(lines)


def main(argv: List[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    if not args.path:
        raise SystemExit("Missing file argument. When used as EDITOR, sops supplies it.")

    target = Path(args.path)
    if not target.exists():
        raise SystemExit(f"File does not exist: {target}")

    rule = build_rule(args)
    try:
        updated = ensure_rule(target, rule, args.after)
    except ValueError as err:
        raise SystemExit(str(err)) from err

    if updated:
        print(f"Added usbguard rule for {rule.device_id} on port {rule.via_port}")
    else:
        print("Rule already present; no changes made.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
