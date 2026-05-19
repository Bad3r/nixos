#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix nixpkgs#yq-go --command python3
"""Update script for webcrack."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, cast


PACKAGE_NAME = "webcrack"
OWNER = "j4k0xb"
REPO = "webcrack"
TAG_PATTERN = r"^v(?P<version>\d+\.\d+\.\d+)$"


SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap, host_package_attr  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
HASHES_FILE = PACKAGE_DIR / "hashes.json"
PACKAGE_ATTR = host_package_attr(FLAKE_ROOT, PACKAGE_NAME)
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_github_latest_tag,
    fetch_json,
    fetch_text,
    load_hashes,
    save_hashes,
)


def latest_version() -> str:
    """Fetch the highest stable webcrack tag."""
    return fetch_github_latest_tag(OWNER, REPO, TAG_PATTERN)


def upstream_url(version: str, path: str) -> str:
    """Return a raw GitHub URL for the tagged webcrack source."""
    return f"https://raw.githubusercontent.com/{OWNER}/{REPO}/v{version}/{path}"


def parse_pnpm_lock(lock_text: str) -> dict[str, Any]:
    """Parse pnpm-lock.yaml with yq."""
    result = subprocess.run(
        ["yq", "-o=json", "."],
        check=True,
        capture_output=True,
        text=True,
        input=lock_text,
    )
    data = json.loads(result.stdout)
    if not isinstance(data, dict):
        msg = f"Expected dict from pnpm lock, got {type(data)}"
        raise TypeError(msg)
    return cast("dict[str, Any]", data)


def upstream_isolated_vm_pin(version: str) -> tuple[str, str]:
    """Read the exact isolated-vm version and integrity from upstream."""
    package_json = fetch_json(upstream_url(version, "packages/webcrack/package.json"))
    if not isinstance(package_json, dict):
        msg = f"Expected package.json dict, got {type(package_json)}"
        raise TypeError(msg)

    dependencies = package_json.get("dependencies")
    if not isinstance(dependencies, dict):
        msg = f"Expected dependencies dict, got {type(dependencies)}"
        raise TypeError(msg)
    package_specifier = dependencies.get("isolated-vm")
    if not isinstance(package_specifier, str):
        msg = "Could not find isolated-vm in packages/webcrack/package.json"
        raise RuntimeError(msg)

    lock_text = fetch_text(upstream_url(version, "pnpm-lock.yaml"))
    lock_data = parse_pnpm_lock(lock_text)
    importers = lock_data.get("importers")
    if not isinstance(importers, dict):
        msg = f"Expected importers dict, got {type(importers)}"
        raise TypeError(msg)

    webcrack_importer = importers.get("packages/webcrack")
    if not isinstance(webcrack_importer, dict):
        msg = "Could not find packages/webcrack importer in pnpm-lock.yaml"
        raise RuntimeError(msg)
    importer_deps = webcrack_importer.get("dependencies")
    if not isinstance(importer_deps, dict):
        msg = f"Expected importer dependencies dict, got {type(importer_deps)}"
        raise TypeError(msg)

    isolated_vm = importer_deps.get("isolated-vm")
    if not isinstance(isolated_vm, dict):
        msg = "Could not find isolated-vm importer entry in pnpm-lock.yaml"
        raise RuntimeError(msg)

    lock_specifier = isolated_vm.get("specifier")
    lock_version = isolated_vm.get("version")
    if lock_specifier != package_specifier:
        msg = (
            "isolated-vm package.json specifier does not match pnpm lock: "
            f"{package_specifier} != {lock_specifier}"
        )
        raise RuntimeError(msg)
    if not isinstance(lock_version, str):
        msg = f"Expected isolated-vm version string, got {type(lock_version)}"
        raise TypeError(msg)

    packages = lock_data.get("packages")
    if not isinstance(packages, dict):
        msg = f"Expected packages dict, got {type(packages)}"
        raise TypeError(msg)
    package_key_suffix = f"isolated-vm@{lock_version}"
    package_entry = next(
        (entry for key, entry in packages.items() if key.endswith(package_key_suffix)),
        None,
    )
    if package_entry is None:
        msg = f"Could not find isolated-vm@{lock_version} in pnpm-lock.yaml"
        raise RuntimeError(msg)
    if not isinstance(package_entry, dict):
        msg = f"Expected isolated-vm package entry dict, got {type(package_entry)}"
        raise TypeError(msg)
    resolution = package_entry.get("resolution")
    if not isinstance(resolution, dict):
        msg = f"Expected isolated-vm resolution dict, got {type(resolution)}"
        raise TypeError(msg)
    integrity = resolution.get("integrity")
    if not isinstance(integrity, str):
        msg = f"Expected isolated-vm integrity string, got {type(integrity)}"
        raise TypeError(msg)

    return lock_version, integrity


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
    """Update webcrack to the latest stable tag."""
    args = parse_args()
    data = load_hashes(HASHES_FILE)
    current = cast("str", data["version"])
    latest = latest_version()
    isolated_vm_version, isolated_vm_integrity = upstream_isolated_vm_pin(latest)

    print(f"Current:     {current}")
    print(f"Latest:      {latest}")
    print(f"isolated-vm: {isolated_vm_version}")

    if args.check_release:
        print("Release metadata is valid")
        return

    needs_pin_update = (
        data.get("isolatedVmVersion") != isolated_vm_version
        or data.get("isolatedVmIntegrity") != isolated_vm_integrity
    )
    if current == latest and not needs_pin_update and not args.force:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = calculate_url_hash(
        f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz",
        unpack=True,
    )

    new_data: dict[str, Any] = {
        "version": latest,
        "srcHash": src_hash,
        "pnpmDepsHash": data.get("pnpmDepsHash", ""),
        "isolatedVmVersion": isolated_vm_version,
        "isolatedVmIntegrity": isolated_vm_integrity,
        "simdutfVersion": data["simdutfVersion"],
        "simdutfHash": data["simdutfHash"],
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
