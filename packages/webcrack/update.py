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


def require_dict(value: object, description: str) -> dict[str, Any]:
    """Return a JSON object or raise a typed error."""
    if not isinstance(value, dict):
        msg = f"Expected {description} dict, got {type(value)}"
        raise TypeError(msg)
    return cast("dict[str, Any]", value)


def require_str(value: object, description: str) -> str:
    """Return a JSON string or raise a typed error."""
    if not isinstance(value, str):
        msg = f"Expected {description} string, got {type(value)}"
        raise TypeError(msg)
    return value


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
    return require_dict(data, "pnpm lock")


def package_json_isolated_vm_specifier(version: str) -> str:
    """Read the isolated-vm specifier from upstream package.json."""
    package_json = require_dict(
        fetch_json(upstream_url(version, "packages/webcrack/package.json")),
        "package.json",
    )
    dependencies = require_dict(package_json.get("dependencies"), "dependencies")
    return require_str(
        dependencies.get("isolated-vm"),
        "isolated-vm dependency in packages/webcrack/package.json",
    )


def importer_isolated_vm_entry(lock_data: dict[str, Any]) -> dict[str, Any]:
    """Read the isolated-vm importer entry from pnpm-lock.yaml."""
    importers = require_dict(lock_data.get("importers"), "importers")
    webcrack_importer = require_dict(
        importers.get("packages/webcrack"),
        "packages/webcrack importer",
    )
    importer_deps = require_dict(webcrack_importer.get("dependencies"), "importer dependencies")
    return require_dict(importer_deps.get("isolated-vm"), "isolated-vm importer entry")


def package_entry_for_isolated_vm(
    packages: dict[str, Any],
    lock_version: str,
) -> dict[str, Any]:
    """Read the isolated-vm package entry from pnpm-lock.yaml packages."""
    package_key_suffix = f"isolated-vm@{lock_version}"
    package_entry = next(
        (entry for key, entry in packages.items() if key.endswith(package_key_suffix)),
        None,
    )
    if package_entry is None:
        msg = f"Could not find isolated-vm@{lock_version} in pnpm-lock.yaml"
        raise RuntimeError(msg)
    return require_dict(package_entry, "isolated-vm package entry")


def lockfile_isolated_vm_integrity(lock_data: dict[str, Any], lock_version: str) -> str:
    """Read the isolated-vm package integrity from pnpm-lock.yaml."""
    packages = require_dict(lock_data.get("packages"), "packages")
    package_entry = package_entry_for_isolated_vm(packages, lock_version)
    resolution = require_dict(package_entry.get("resolution"), "isolated-vm resolution")
    return require_str(resolution.get("integrity"), "isolated-vm integrity")


def upstream_isolated_vm_pin(version: str) -> tuple[str, str]:
    """Read the exact isolated-vm version and integrity from upstream."""
    package_specifier = package_json_isolated_vm_specifier(version)
    lock_text = fetch_text(upstream_url(version, "pnpm-lock.yaml"))
    lock_data = parse_pnpm_lock(lock_text)
    isolated_vm = importer_isolated_vm_entry(lock_data)
    lock_specifier = require_str(isolated_vm.get("specifier"), "isolated-vm specifier")
    lock_version = require_str(isolated_vm.get("version"), "isolated-vm version")
    if lock_specifier != package_specifier:
        msg = (
            "isolated-vm package.json specifier does not match pnpm lock: "
            f"{package_specifier} != {lock_specifier}"
        )
        raise RuntimeError(msg)
    return lock_version, lockfile_isolated_vm_integrity(lock_data, lock_version)


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
