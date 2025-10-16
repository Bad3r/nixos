#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

try:
    import package_utils
except ImportError as exc:  # pragma: no cover
    raise SystemExit(f"failed to import package_utils: {exc}") from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Phase 4 workstation parity validation")
    parser.add_argument("--manifest", required=True, help="Path to expected workstation manifest JSON")
    parser.add_argument("--actual", required=True, help="Path to actual package list JSON map")
    parser.add_argument("--host", default="system76", help="Host key to evaluate (default: system76)")
    parser.add_argument(
        "--repo",
        help="Repository root (used for logging); defaults to derived path",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest).resolve()
    actual_path = Path(args.actual).resolve()

    try:
        expected = package_utils.collect_names("manifest", manifest_path)
        actual = package_utils.collect_names("actual", actual_path, host=args.host)
    except ValueError as exc:
        print(f"workstation-parity: {exc}", file=sys.stderr)
        return 1

    diff = package_utils.compare_sets(expected, actual)
    if diff.is_clean:
        print(
            f"workstation-parity: {args.host} matches {manifest_path.name} ({len(expected)} packages)",
            file=sys.stdout,
        )
        return 0

    print(
        f"workstation-parity: {args.host} diverges from {manifest_path}",
        file=sys.stderr,
    )
    if diff.missing:
        print("  missing:", file=sys.stderr)
        for name in diff.missing:
            print(f"    {name}", file=sys.stderr)
    if diff.unexpected:
        print("  unexpected:", file=sys.stderr)
        for name in diff.unexpected:
            print(f"    {name}", file=sys.stderr)
    return 2


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
