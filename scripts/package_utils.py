#!/usr/bin/env python3

"""
Utilities for normalizing and comparing package name manifests.

This module exposes helpers that strip Nix store hashes and version
suffixes so that package sets can be compared consistently across
different derivations.  It can be used as both an importable module
and a small CLI entrypoint.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence, Set

STORE_HASH_PATTERN = re.compile(r"^([0-9a-z]{32})-")
VERSION_PATTERN = re.compile(r"-[0-9].*$")


def normalize_name(raw: object) -> str:
    """Strip store hash prefixes and version suffixes from a package name."""
    name = str(raw)
    name = STORE_HASH_PATTERN.sub("", name)
    name = VERSION_PATTERN.sub("", name)
    return name


def _load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text())
    except Exception as exc:  # pragma: no cover - surfaced to caller
        raise ValueError(f"failed to parse JSON from {path}: {exc}") from exc


def _collect_from_manifest(path: Path) -> Set[str]:
    data = _load_json(path)
    if not isinstance(data, Sequence):
        raise ValueError(f"expected manifest {path} to be a JSON array")
    return {normalize_name(item) for item in data if item}


def _collect_from_role_inventory(path: Path) -> Set[str]:
    data = _load_json(path)
    if not isinstance(data, dict):
        raise ValueError(f"expected role inventory {path} to be a JSON object")
    collected: Set[str] = set()
    for info in data.values():
        if isinstance(info, dict):
            apps = info.get("apps", [])
            for app in apps or []:
                collected.add(normalize_name(app))
    return collected


def _collect_from_actual(path: Path, host: str) -> Set[str]:
    data = _load_json(path)
    if not isinstance(data, dict):
        raise ValueError(f"expected actual package map {path} to be a JSON object")
    if host not in data:
        raise ValueError(f"host '{host}' missing from {path}")
    packages = data[host]
    if not isinstance(packages, Sequence):
        raise ValueError(f"expected package list for host '{host}' to be an array")
    return {normalize_name(item) for item in packages if item}


def _collect_from_lines(path: Path) -> Set[str]:
    collected: Set[str] = set()
    with path.open() as handle:
        for line in handle:
            entry = line.strip()
            if entry:
                collected.add(normalize_name(entry))
    return collected


def collect_names(mode: str, path: Path, host: str | None = None) -> List[str]:
    """
    Load and normalize package names from the given path.

    Modes:
        manifest        - JSON array of package names.
        role-inventory  - JSON object mapping roles to metadata (expects `apps` lists).
        actual          - JSON map of host -> package array (requires host argument).
        lines           - Plain text file with one package per line.
    """
    if mode == "manifest":
        items = _collect_from_manifest(path)
    elif mode == "role-inventory":
        items = _collect_from_role_inventory(path)
    elif mode == "actual":
        if not host:
            raise ValueError("host argument is required for mode 'actual'")
        items = _collect_from_actual(path, host)
    elif mode == "lines":
        items = _collect_from_lines(path)
    else:
        raise ValueError(f"unknown mode '{mode}'")

    return sorted(item for item in items if item)


@dataclass(frozen=True)
class Diff:
    missing: List[str]
    unexpected: List[str]

    @property
    def is_clean(self) -> bool:
        return not self.missing and not self.unexpected


def compare_sets(expected: Iterable[str], actual: Iterable[str]) -> Diff:
    expected_set = set(expected)
    actual_set = set(actual)
    missing = sorted(expected_set - actual_set)
    unexpected = sorted(actual_set - expected_set)
    return Diff(missing=missing, unexpected=unexpected)


def _cmd_normalize(args: argparse.Namespace) -> int:
    path = Path(args.input).resolve()
    try:
        names = collect_names(args.mode, path, host=args.host)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    output = "\n".join(names)
    if args.output:
        dest = Path(args.output).resolve()
        dest.write_text(output + ("\n" if output else ""))
    else:
        if output:
            print(output)
    return 0


def _cmd_compare(args: argparse.Namespace) -> int:
    manifest_path = Path(args.manifest).resolve()
    actual_path = Path(args.actual).resolve()
    try:
        expected = collect_names("manifest", manifest_path)
        actual = collect_names("actual", actual_path, host=args.host)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    diff = compare_sets(expected, actual)
    if diff.is_clean:
        if not args.quiet:
            print(f"parity ok: {args.host} matches manifest ({len(expected)} packages)")
        return 0

    if diff.missing:
        print("missing:", file=sys.stderr)
        for name in diff.missing:
            print(f"  {name}", file=sys.stderr)
    if diff.unexpected:
        print("unexpected:", file=sys.stderr)
        for name in diff.unexpected:
            print(f"  {name}", file=sys.stderr)
    return 2


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Package normalization utilities")
    sub = parser.add_subparsers(dest="command", required=True)

    normalize = sub.add_parser("normalize", help="normalize package names from a source")
    normalize.add_argument("--mode", choices=["manifest", "role-inventory", "actual", "lines"], required=True)
    normalize.add_argument("--input", required=True, help="path to input data")
    normalize.add_argument("--host", help="host to select (mode=actual)")
    normalize.add_argument("--output", help="path to write normalized names")
    normalize.set_defaults(func=_cmd_normalize)

    compare = sub.add_parser("compare", help="compare manifest vs actual package sets")
    compare.add_argument("--manifest", required=True, help="manifest JSON file")
    compare.add_argument("--actual", required=True, help="actual packages JSON file")
    compare.add_argument("--host", required=True, help="host key inside the actual packages map")
    compare.add_argument("--quiet", action="store_true", help="suppress success output")
    compare.set_defaults(func=_cmd_compare)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    sys.exit(main())
