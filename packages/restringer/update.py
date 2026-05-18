#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for restringer."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, cast


PACKAGE_NAME = "restringer"
OWNER = "HumanSecurity"
REPO = "restringer"
TAG_PATTERN = r"^v(?P<version>\d+\.\d+\.\d+)$"
DEFAULT_NODE_ABI = "node-v127"
DEFAULT_PLATFORM = "linux-x64"


_CWD = Path.cwd().resolve()
sys.path[:0] = [
    str(root / "scripts")
    for root in [_CWD, *_CWD.parents]
    if (root / "scripts" / "updater_bootstrap.py").is_file()
]

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(PACKAGE_NAME)
HASHES_FILE = PACKAGE_DIR / "hashes.json"
PACKAGE_ATTR = f"{FLAKE_ROOT}#restringer"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_github_latest_tag,
    fetch_json,
    load_hashes,
    save_hashes,
)


def latest_version() -> str:
    """Fetch the highest stable restringer tag."""
    return fetch_github_latest_tag(OWNER, REPO, TAG_PATTERN)


def upstream_url(version: str, path: str) -> str:
    """Return a raw GitHub URL for the tagged restringer source."""
    return f"https://raw.githubusercontent.com/{OWNER}/{REPO}/v{version}/{path}"


def package_json_isolated_vm_version(version: str) -> str:
    """Read an exact isolated-vm dependency from package.json."""
    data = fetch_json(upstream_url(version, "package.json"))
    if not isinstance(data, dict):
        msg = f"Expected package.json dict, got {type(data)}"
        raise TypeError(msg)

    dependencies = data.get("dependencies")
    if not isinstance(dependencies, dict):
        msg = f"Expected dependencies dict, got {type(dependencies)}"
        raise TypeError(msg)
    isolated_vm = dependencies.get("isolated-vm")
    if not isinstance(isolated_vm, str):
        msg = "Could not find isolated-vm in package.json"
        raise RuntimeError(msg)
    if not isolated_vm[0].isdigit():
        msg = f"package.json isolated-vm dependency is not exact: {isolated_vm}"
        raise RuntimeError(msg)
    return isolated_vm


def lockfile_isolated_vm_version(version: str) -> str | None:
    """Read the exact isolated-vm dependency from package-lock.json."""
    data = fetch_json(upstream_url(version, "package-lock.json"))
    if not isinstance(data, dict):
        msg = f"Expected package-lock.json dict, got {type(data)}"
        raise TypeError(msg)

    packages = data.get("packages")
    if isinstance(packages, dict):
        package_entry = packages.get("node_modules/isolated-vm")
        if isinstance(package_entry, dict):
            lock_version = package_entry.get("version")
            if isinstance(lock_version, str):
                return lock_version

    dependencies = data.get("dependencies")
    if isinstance(dependencies, dict):
        dependency_entry = dependencies.get("isolated-vm")
        if isinstance(dependency_entry, dict):
            lock_version = dependency_entry.get("version")
            if isinstance(lock_version, str):
                return lock_version

    return None


def upstream_isolated_vm_version(version: str) -> str:
    """Find the exact isolated-vm version used by upstream."""
    lock_version = lockfile_isolated_vm_version(version)
    if lock_version is not None:
        return lock_version
    return package_json_isolated_vm_version(version)


def isolated_vm_prebuild_url(
    isolated_vm_version: str,
    node_abi: str,
    platform: str,
) -> str:
    """Return the isolated-vm prebuild URL for the supported platform."""
    archive = f"isolated-vm-v{isolated_vm_version}-{node_abi}-{platform}.tar.gz"
    return (
        "https://github.com/laverdet/isolated-vm/releases/download/"
        f"v{isolated_vm_version}/{archive}"
    )


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
    """Update restringer to the latest stable tag."""
    args = parse_args()
    data = load_hashes(HASHES_FILE)
    current = cast("str", data["version"])
    latest = latest_version()
    isolated_vm_version = upstream_isolated_vm_version(latest)
    node_abi = cast("str", data.get("isolatedVmNodeAbi", DEFAULT_NODE_ABI))
    platform = cast("str", data.get("isolatedVmPlatform", DEFAULT_PLATFORM))

    print(f"Current:     {current}")
    print(f"Latest:      {latest}")
    print(f"isolated-vm: {isolated_vm_version}")
    print(f"Prebuild:    {node_abi}-{platform}")

    if args.check_release:
        print("Release metadata is valid")
        return

    native_pin_changed = (
        data.get("isolatedVmVersion") != isolated_vm_version
        or data.get("isolatedVmNodeAbi") != node_abi
        or data.get("isolatedVmPlatform") != platform
    )
    if current == latest and not native_pin_changed and not args.force:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = calculate_url_hash(
        f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz",
        unpack=True,
    )

    if native_pin_changed:
        print("Calculating isolated-vm prebuild hash...")
        prebuild_hash = calculate_url_hash(
            isolated_vm_prebuild_url(isolated_vm_version, node_abi, platform),
        )
    else:
        prebuild_hash = cast("str", data["isolatedVmPrebuildHash"])

    new_data: dict[str, Any] = {
        "version": latest,
        "srcHash": src_hash,
        "npmDepsHash": data.get("npmDepsHash", ""),
        "isolatedVmVersion": isolated_vm_version,
        "isolatedVmNodeAbi": node_abi,
        "isolatedVmPlatform": platform,
        "isolatedVmPrebuildHash": prebuild_hash,
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
