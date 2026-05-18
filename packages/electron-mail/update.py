#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for electron-mail."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any, cast


REPO = "vladimiry/ElectronMail"
PACKAGE_NAME = "electron-mail"
ASSET_SUFFIXES = {
    "x86_64-linux": "linux-x86_64.AppImage",
    "aarch64-darwin": "mac-arm64.dmg",
    "x86_64-darwin": "mac-x64.dmg",
}
URL_TEMPLATE = (
    "https://github.com/vladimiry/ElectronMail/releases/download/"
    "v{version}/electron-mail-{version}-{platform}"
)


_CWD = Path.cwd().resolve()
sys.path[:0] = [
    str(root / "scripts")
    for root in [_CWD, *_CWD.parents]
    if (root / "scripts" / "updater_bootstrap.py").is_file()
]

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(PACKAGE_NAME)
PACKAGE_FILE = PACKAGE_DIR / "default.nix"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import calculate_platform_hashes, fetch_json  # noqa: E402


def latest_release() -> tuple[str, set[str]]:
    """Fetch the latest GitHub release version and its asset names."""
    data = fetch_json(f"https://api.github.com/repos/{REPO}/releases/latest")
    if not isinstance(data, dict):
        msg = f"Expected dict from GitHub API, got {type(data)}"
        raise TypeError(msg)

    tag = cast("str", data["tag_name"])
    assets = cast("list[dict[str, Any]]", data["assets"])
    return tag.removeprefix("v"), {cast("str", asset["name"]) for asset in assets}


def current_version(text: str) -> str:
    """Read the packaged version from default.nix."""
    match = re.search(r'^  version = "([^"]+)";$', text, flags=re.MULTILINE)
    if match is None:
        msg = f"Could not find {PACKAGE_NAME} version in {PACKAGE_FILE}"
        raise RuntimeError(msg)
    return match.group(1)


def required_assets(version: str) -> dict[str, str]:
    """Return expected GitHub asset names by Nix platform."""
    return {
        platform: f"electron-mail-{version}-{suffix}"
        for platform, suffix in ASSET_SUFFIXES.items()
    }


def replace_once(text: str, pattern: str, replacement: str, description: str) -> str:
    """Replace exactly one match in default.nix."""
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        msg = f"Expected one {description} match in {PACKAGE_FILE}, found {count}"
        raise RuntimeError(msg)
    return updated


def update_hash(text: str, platform: str, suffix: str, hash_value: str) -> str:
    """Update the fetchurl hash for one platform source."""
    url = (
        "https://github.com/vladimiry/ElectronMail/releases/download/"
        f"v${{version}}/electron-mail-${{version}}-{suffix}"
    )
    pattern = (
        rf"(?P<prefix>    {re.escape(platform)} = fetchurl \{{\n"
        rf'      url = "{re.escape(url)}";\n'
        r'      hash = ")[^"]+(?P<suffix>";\n'
        r"    \};)"
    )
    replacement = rf"\g<prefix>{hash_value}\g<suffix>"
    return replace_once(text, pattern, replacement, f"{platform} hash")


def update_package_file(version: str, hashes: dict[str, str]) -> bool:
    """Write the updated version and source hashes to default.nix."""
    text = PACKAGE_FILE.read_text(encoding="utf-8")
    updated = replace_once(
        text,
        r'^  version = "[^"]+";$',
        f'  version = "{version}";',
        "version",
    )
    for platform, suffix in ASSET_SUFFIXES.items():
        updated = update_hash(updated, platform, suffix, hashes[platform])

    if updated == text:
        return False

    PACKAGE_FILE.write_text(updated, encoding="utf-8")
    return True


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--force",
        action="store_true",
        help="recalculate source hashes even when the version is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Update electron-mail to the latest GitHub release."""
    args = parse_args()
    package_text = PACKAGE_FILE.read_text(encoding="utf-8")
    current = current_version(package_text)
    latest, release_assets = latest_release()
    print(f"Current: {current}")
    print(f"Latest:  {latest}")

    if current == latest and not args.force:
        print("Already up to date")
        return

    expected_assets = required_assets(latest)
    missing_assets = sorted(set(expected_assets.values()) - release_assets)
    if missing_assets:
        print("Missing expected release assets:", file=sys.stderr)
        for asset in missing_assets:
            print(f"  - {asset}", file=sys.stderr)
        sys.exit(1)

    hashes = calculate_platform_hashes(
        URL_TEMPLATE,
        ASSET_SUFFIXES,
        version=latest,
    )
    changed = update_package_file(latest, hashes)
    if changed:
        print(f"Updated {PACKAGE_FILE.relative_to(FLAKE_ROOT)} to {latest}")
    else:
        print(f"{PACKAGE_FILE.relative_to(FLAKE_ROOT)} already matches {latest}")


if __name__ == "__main__":
    main()
