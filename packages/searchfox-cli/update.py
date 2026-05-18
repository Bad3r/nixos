#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3
"""Update script for searchfox-cli."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, cast


PACKAGE_NAME = "searchfox-cli"
REPO = "padenot/searchfox-cli"


_CWD = Path.cwd().resolve()
sys.path[:0] = [
    str(root / "scripts")
    for root in [_CWD, *_CWD.parents]
    if (root / "scripts" / "updater_bootstrap.py").is_file()
]

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(PACKAGE_NAME)
HASHES_FILE = PACKAGE_DIR / "hashes.json"
PACKAGE_ATTR = f"{FLAKE_ROOT}#nixosConfigurations.system76.pkgs.{PACKAGE_NAME}"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_json,
    load_hashes,
    save_hashes,
)


def latest_crate_version() -> str:
    """Fetch the latest published searchfox-cli version from crates.io."""
    data = fetch_json(f"https://crates.io/api/v1/crates/{PACKAGE_NAME}")
    if not isinstance(data, dict):
        msg = f"Expected dict from crates.io API, got {type(data)}"
        raise TypeError(msg)

    crate = cast("dict[str, Any]", data["crate"])
    version = crate.get("max_stable_version") or crate["max_version"]
    if not isinstance(version, str):
        msg = f"Expected string version from crates.io API, got {type(version)}"
        raise TypeError(msg)
    return version


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--force",
        action="store_true",
        help="recalculate hashes even when the version is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Update searchfox-cli to the latest crates.io release."""
    args = parse_args()
    data = load_hashes(HASHES_FILE)
    current = cast("str", data["version"])
    latest = latest_crate_version()

    print(f"Current: {current}")
    print(f"Latest:  {latest}")

    if current == latest and not args.force:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = calculate_url_hash(
        f"https://github.com/{REPO}/archive/refs/tags/v{latest}.tar.gz",
        unpack=True,
    )

    new_data: dict[str, Any] = {
        "version": latest,
        "srcHash": src_hash,
        "cargoHash": data.get("cargoHash", ""),
    }

    new_data["cargoHash"] = calculate_dependency_hash(
        PACKAGE_ATTR,
        "cargoHash",
        HASHES_FILE,
        new_data,
    )
    save_hashes(HASHES_FILE, new_data)
    print(f"Updated {HASHES_FILE.relative_to(FLAKE_ROOT)} to {latest}")


if __name__ == "__main__":
    main()
