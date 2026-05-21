#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for age-plugin-fido2prf."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import cast

PACKAGE_NAME = "age-plugin-fido2prf"
OWNER = "FiloSottile"
REPO = "typage"

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from updater_bootstrap import bootstrap, host_package_attr  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
HASHES_FILE = PACKAGE_DIR / "hashes.json"
PACKAGE_ATTR = host_package_attr(FLAKE_ROOT, PACKAGE_NAME)
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
    """Update age-plugin-fido2prf to the latest stable GitHub tag."""
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
        "vendorHash": data.get("vendorHash", ""),
    }

    new_data["vendorHash"] = calculate_dependency_hash(
        PACKAGE_ATTR,
        "vendorHash",
        HASHES_FILE,
        new_data,
    )
    save_hashes(HASHES_FILE, new_data)
    print(f"Updated {HASHES_FILE.relative_to(FLAKE_ROOT)} to {latest}")


if __name__ == "__main__":
    main()
