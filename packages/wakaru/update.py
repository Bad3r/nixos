#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for wakaru."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, cast


PACKAGE_NAME = "wakaru"
OWNER = "pionxzh"
REPO = "wakaru"
TAG_PATTERN = r"^cli-v(?P<version>\d+\.\d+\.\d+)$"


def _find_scripts_dir(start: Path) -> Path | None:
    """Walk up from ``start`` until this checkout's scripts dir is found."""
    for parent in [start, *start.parents]:
        scripts_dir = parent / "scripts"
        if (
            (parent / "flake.nix").is_file()
            and (scripts_dir / "updater_bootstrap.py").is_file()
            and (parent / "packages" / PACKAGE_NAME / "default.nix").is_file()
        ):
            return scripts_dir
    return None


def _add_bootstrap_import_path() -> None:
    """Make updater_bootstrap importable from cwd or the checkout script path."""
    starts = [
        Path.cwd().resolve(),
        Path(__file__).resolve().parent,
    ]
    for start in starts:
        scripts_dir = _find_scripts_dir(start)
        if scripts_dir is not None:
            sys.path.insert(0, str(scripts_dir))
            return

    msg = (
        "Could not find the nixos checkout scripts directory. Run this updater "
        "from the repository checkout, or execute the checkout copy under "
        f"packages/{PACKAGE_NAME}/."
    )
    raise RuntimeError(msg)


_add_bootstrap_import_path()

from updater_bootstrap import bootstrap, host_package_attr  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
HASHES_FILE = PACKAGE_DIR / "hashes.json"
PACKAGE_ATTR = host_package_attr(FLAKE_ROOT, PACKAGE_NAME)
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_github_latest_tag,
    load_hashes,
    save_hashes,
)


def latest_version() -> str:
    """Fetch the highest stable wakaru CLI tag."""
    return fetch_github_latest_tag(OWNER, REPO, TAG_PATTERN)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check-release",
        action="store_true",
        help="validate release metadata without fetching hashes",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="recalculate hashes even when the version is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Update wakaru to the latest CLI tag."""
    args = parse_args()
    data = load_hashes(HASHES_FILE)
    current = cast("str", data["version"])
    latest = latest_version()

    print(f"Current: {current}")
    print(f"Latest:  {latest}")
    print(f"Tag:     cli-v{latest}")

    if args.check_release:
        print("Release metadata is valid")
        return

    if current == latest and not args.force:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = calculate_url_hash(
        f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/cli-v{latest}.tar.gz",
        unpack=True,
    )

    new_data: dict[str, Any] = {
        "version": latest,
        "srcHash": src_hash,
        "pnpmDepsHash": data.get("pnpmDepsHash", ""),
    }
    new_data["pnpmDepsHash"] = calculate_dependency_hash(
        PACKAGE_ATTR,
        "pnpmDepsHash",
        HASHES_FILE,
        new_data,
    )
    save_hashes(HASHES_FILE, new_data)
    print(f"Updated {HASHES_FILE.relative_to(FLAKE_ROOT)} to {latest}")


if __name__ == "__main__":
    main()
