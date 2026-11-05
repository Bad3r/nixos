#!/usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3
# Copyright (c) 2026 Bad3r

"""Update script for brave-origin."""

from __future__ import annotations

import argparse
import base64
import re
import sys
from pathlib import Path

PACKAGE_NAME = "brave-origin"
VERSION_URL = "https://versions.brave.com/latest/origin-{channel}.version"
VERSION_CHANNELS = ("release-linux-x64", "release-linux-arm64")
ASSET_SUFFIXES = {
    "x86_64-linux": "amd64.deb",
    "aarch64-linux": "arm64.deb",
}
URL_TEMPLATE = (
    "https://github.com/brave/brave-browser/releases/download/"
    "v{version}/brave-origin_{version}_{suffix}"
)


SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
PACKAGE_FILE = PACKAGE_DIR / "default.nix"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import fetch_text  # noqa: E402


def latest_version() -> str:
    """Return the Origin release version, which every Linux channel must agree on."""
    versions = {
        fetch_text(VERSION_URL.format(channel=channel)).strip() for channel in VERSION_CHANNELS
    }
    if len(versions) != 1:
        msg = f"Brave Origin Linux channels disagree on the latest version: {sorted(versions)}"
        raise RuntimeError(msg)
    version = versions.pop()
    if not re.fullmatch(r"\d+(\.\d+)+", version):
        msg = f"Unexpected Brave Origin version string: {version!r}"
        raise RuntimeError(msg)
    return version


def sri_hash(version: str, suffix: str) -> str:
    """Read the published sha256 of one release asset as an SRI hash."""
    url = URL_TEMPLATE.format(version=version, suffix=suffix) + ".sha256"
    digest = fetch_text(url).split()[0]
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        msg = f"Unexpected sha256 in {url}: {digest!r}"
        raise RuntimeError(msg)
    return "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode("ascii")


def current_version(text: str) -> str:
    """Read the packaged version from default.nix."""
    match = re.search(r'^  version = "([^"]+)";$', text, flags=re.MULTILINE)
    if match is None:
        msg = f"Could not find {PACKAGE_NAME} version in {PACKAGE_FILE}"
        raise RuntimeError(msg)
    return match.group(1)


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
        "https://github.com/brave/brave-browser/releases/download/"
        f"v${{version}}/brave-origin_${{version}}_{suffix}"
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
        help="re-read source hashes even when the version is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Update brave-origin to the latest Brave Origin release."""
    args = parse_args()
    current = current_version(PACKAGE_FILE.read_text(encoding="utf-8"))
    latest = latest_version()
    print(f"Current: {current}")
    print(f"Latest:  {latest}")

    if current == latest and not args.force:
        print("Already up to date")
        return

    hashes = {platform: sri_hash(latest, suffix) for platform, suffix in ASSET_SUFFIXES.items()}
    if update_package_file(latest, hashes):
        print(f"Updated {PACKAGE_FILE.relative_to(FLAKE_ROOT)} to {latest}")
    else:
        print(f"{PACKAGE_FILE.relative_to(FLAKE_ROOT)} already matches {latest}")


if __name__ == "__main__":
    main()
