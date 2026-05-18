#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for source-map-explorer."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import cast


PACKAGE_NAME = "source-map-explorer"
OWNER = "danvk"
REPO = "source-map-explorer"


def _flake_root(start: Path) -> Path | None:
    """Walk up from ``start`` until this checkout's flake root is found."""
    for parent in [start, *start.parents]:
        if (
            (parent / "flake.nix").is_file()
            and (parent / "scripts" / "updater").is_dir()
            and (parent / "packages" / PACKAGE_NAME / "default.nix").is_file()
        ):
            return parent
    return None


def _checkout_root() -> Path:
    """Find the editable checkout from either cwd or the script path."""
    starts = [
        Path.cwd().resolve(),
        Path(__file__).resolve().parent,
    ]
    for start in starts:
        root = _flake_root(start)
        if root is not None:
            return root

    msg = (
        "Could not find the nixos checkout root. Run this updater from the "
        "repository checkout, or execute the checkout copy under "
        f"packages/{PACKAGE_NAME}/."
    )
    raise RuntimeError(msg)


FLAKE_ROOT = _checkout_root()
HASHES_FILE = FLAKE_ROOT / "packages" / PACKAGE_NAME / "hashes.json"
PACKAGE_ATTR = f"{FLAKE_ROOT}#nixosConfigurations.system76.pkgs.{PACKAGE_NAME}"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_github_latest_tag_version,
    load_hashes,
    save_hashes,
)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check-release",
        action="store_true",
        help="validate release metadata without fetching archive hashes",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="recalculate hashes even when the version is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Update source-map-explorer to the latest stable GitHub tag."""
    args = parse_args()
    data = load_hashes(HASHES_FILE)
    current = cast("str", data["version"])
    latest = fetch_github_latest_tag_version(OWNER, REPO)

    print(f"Current: {current}")
    print(f"Latest:  {latest}")

    if args.check_release:
        print("Release metadata is valid")
        return

    if current == latest and not args.force:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = calculate_url_hash(
        f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz",
        unpack=True,
    )

    new_data = {
        "version": latest,
        "srcHash": src_hash,
        "npmDepsHash": data.get("npmDepsHash", ""),
    }

    new_data["npmDepsHash"] = calculate_dependency_hash(
        PACKAGE_ATTR,
        "npmDepsHash",
        HASHES_FILE,
        new_data,
    )
    save_hashes(HASHES_FILE, new_data)
    print(f"Updated {HASHES_FILE.relative_to(FLAKE_ROOT)} to {latest}")


if __name__ == "__main__":
    main()
