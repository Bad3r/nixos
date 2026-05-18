#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for malimite."""

from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path
from typing import Any, cast


PACKAGE_NAME = "malimite"
REPO = "LaurieWired/Malimite"
RELEASES_URL = f"https://api.github.com/repos/{REPO}/releases?per_page=100"
URL_TEMPLATE = (
    "https://github.com/LaurieWired/Malimite/releases/download/{version}/{platform}"
)
TAG_PATTERN = re.compile(r"^(?P<version>[0-9][0-9A-Za-z.+_-]*)$")
ARCHIVE_KEY = "linux"


SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
PACKAGE_FILE = PACKAGE_DIR / "default.nix"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import calculate_platform_hashes, fetch_json  # noqa: E402


def current_version(text: str) -> str:
    """Read the packaged version from default.nix."""
    match = re.search(r'^  version = "([^"]+)";$', text, flags=re.MULTILINE)
    if match is None:
        msg = f"Could not find {PACKAGE_NAME} version in {PACKAGE_FILE}"
        raise RuntimeError(msg)
    return match.group(1)


def release_asset_names(release: dict[str, Any]) -> set[str]:
    """Return the asset names attached to a GitHub release object."""
    assets = release.get("assets")
    if not isinstance(assets, list):
        msg = f"Expected list of release assets, got {type(assets)}"
        raise TypeError(msg)

    names: set[str] = set()
    for asset in assets:
        if not isinstance(asset, dict):
            msg = f"Expected release asset dict, got {type(asset)}"
            raise TypeError(msg)
        name = asset.get("name")
        if not isinstance(name, str):
            msg = f"Expected release asset name string, got {type(name)}"
            raise TypeError(msg)
        names.add(name)
    return names


def archive_name(version: str) -> str:
    """Return the Malimite release archive for ``version``."""
    return f"Malimite-{version.replace('.', '-')}.zip"


def required_assets(version: str) -> dict[str, str]:
    """Return expected GitHub asset names."""
    return {ARCHIVE_KEY: archive_name(version)}


def check_assets(version: str, release_assets: set[str]) -> dict[str, str]:
    """Ensure all required release assets are present."""
    expected = required_assets(version)
    missing_assets = sorted(set(expected.values()) - release_assets)
    if missing_assets:
        missing = "\n  - ".join(missing_assets)
        msg = f"Missing expected release assets:\n  - {missing}"
        raise RuntimeError(msg)
    return expected


def latest_release() -> tuple[str, set[str]]:
    """Fetch the latest non-prerelease GitHub release for this tag scheme."""
    data = fetch_json(RELEASES_URL)
    if not isinstance(data, list):
        msg = f"Expected list from GitHub API, got {type(data)}"
        raise TypeError(msg)

    for release in data:
        if not isinstance(release, dict):
            msg = f"Expected release dict, got {type(release)}"
            raise TypeError(msg)

        draft = release.get("draft")
        prerelease = release.get("prerelease")
        if not isinstance(draft, bool):
            msg = f"Expected release draft boolean, got {type(draft)}"
            raise TypeError(msg)
        if not isinstance(prerelease, bool):
            msg = f"Expected release prerelease boolean, got {type(prerelease)}"
            raise TypeError(msg)
        if draft or prerelease:
            continue

        tag = release.get("tag_name")
        if not isinstance(tag, str):
            msg = f"Expected release tag string, got {type(tag)}"
            raise TypeError(msg)

        match = TAG_PATTERN.fullmatch(tag)
        if match is None:
            continue

        version = match.group("version")
        assets = release_asset_names(cast("dict[str, Any]", release))
        check_assets(version, assets)
        return version, assets

    msg = (
        f"Could not find a stable {PACKAGE_NAME} release matching {TAG_PATTERN.pattern}"
    )
    raise RuntimeError(msg)


def replace_once(
    text: str,
    pattern: str,
    replacement: str,
    description: str,
    *,
    flags: int = 0,
) -> str:
    """Replace exactly one match in default.nix."""
    updated, count = re.subn(
        pattern,
        lambda _match: replacement,
        text,
        count=1,
        flags=flags,
    )
    if count != 1:
        msg = f"Expected one {description} match in {PACKAGE_FILE}, found {count}"
        raise RuntimeError(msg)
    return updated


def render_archives(hash_value: str) -> str:
    """Render the archives attrset."""
    nix_url = URL_TEMPLATE.replace("{version}", "${version}").replace(
        "{platform}",
        "${archiveName}",
    )
    return "\n".join(
        [
            "  archives = {",
            "    linux = {",
            f'      url = "{nix_url}";',
            f'      hash = "{hash_value}";',
            "    };",
            "  };",
        ],
    )


def updated_package_text(version: str, hashes: dict[str, str]) -> str:
    """Return the package expression with updated release metadata."""
    text = PACKAGE_FILE.read_text(encoding="utf-8")
    updated = replace_once(
        text,
        r'^  version = "[^"]+";$',
        f'  version = "{version}";',
        "version",
        flags=re.MULTILINE,
    )
    return replace_once(
        updated,
        r"^  archives = \{\n.*?^  \};",
        render_archives(hashes[ARCHIVE_KEY]),
        "archives attrset",
        flags=re.MULTILINE | re.DOTALL,
    )


def print_diff(before: str, after: str) -> None:
    """Print a unified diff for a dry run."""
    package_path = str(PACKAGE_FILE.relative_to(FLAKE_ROOT))
    for line in difflib.unified_diff(
        before.splitlines(),
        after.splitlines(),
        fromfile=package_path,
        tofile=package_path,
        lineterm="",
    ):
        print(line)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check-release",
        action="store_true",
        help="validate release metadata without fetching archive hashes",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="calculate the update without writing default.nix",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="recalculate source hashes even when the version is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Update malimite to the latest GitHub release."""
    args = parse_args()
    package_text = PACKAGE_FILE.read_text(encoding="utf-8")
    current = current_version(package_text)
    latest, release_assets = latest_release()
    assets = check_assets(latest, release_assets)

    print(f"Current: {current}")
    print(f"Latest:  {latest}")
    print(f"Assets:  {', '.join(assets.values())}")

    if args.check_release:
        print("Release metadata is valid")
        return

    if current == latest and not args.force:
        print("Already up to date")
        return

    hashes = calculate_platform_hashes(
        URL_TEMPLATE,
        assets,
        unpack=True,
        version=latest,
    )
    updated = updated_package_text(latest, hashes)

    if updated == package_text:
        print(f"{PACKAGE_FILE.relative_to(FLAKE_ROOT)} already matches {latest}")
        return

    if args.dry_run:
        print_diff(package_text, updated)
        return

    PACKAGE_FILE.write_text(updated, encoding="utf-8")
    print(f"Updated {PACKAGE_FILE.relative_to(FLAKE_ROOT)} to {latest}")


if __name__ == "__main__":
    main()
