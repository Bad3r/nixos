#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for wfuzz."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PACKAGE_NAME = "wfuzz"
OWNER = "xmendez"
REPO = "wfuzz"

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from updater_bootstrap import bootstrap, host_package_attr  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
PACKAGE_FILE = PACKAGE_DIR / "default.nix"
PACKAGE_ATTR = host_package_attr(FLAKE_ROOT, PACKAGE_NAME)
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_url_hash,
    fetch_github_latest_tag_version,
    nix_build,
)


def current_version(text: str) -> str:
    """Read the packaged version from default.nix."""
    match = re.search(r'^  version = "([^"]+)";$', text, flags=re.MULTILINE)
    if match is None:
        msg = f"Could not find {PACKAGE_NAME} version in {PACKAGE_FILE}"
        raise RuntimeError(msg)
    return match.group(1)


def replace_once(
    text: str,
    pattern: str,
    replacement: str,
    description: str,
    *,
    flags: int = 0,
) -> str:
    """Replace exactly one match in default.nix."""
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        msg = f"Expected one {description} match in {PACKAGE_FILE}, found {count}"
        raise RuntimeError(msg)
    return updated


def updated_package_text(version: str, src_hash: str) -> str:
    """Return default.nix with updated version and source hash."""
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
        (
            r"(?P<prefix>  src = fetchFromGitHub \{\n"
            r'    owner = "xmendez";\n'
            r'    repo = "wfuzz";\n'
            r'    tag = "v\$\{finalAttrs\.version\}";\n'
            r'    hash = ")[^"]+(?P<suffix>";\n'
            r"  \};)"
        ),
        rf"\g<prefix>{src_hash}\g<suffix>",
        "source hash",
        flags=re.MULTILINE,
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
    """Update wfuzz to the latest stable GitHub tag."""
    args = parse_args()
    package_text = PACKAGE_FILE.read_text(encoding="utf-8")
    current = current_version(package_text)
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
    updated = updated_package_text(latest, src_hash)

    if updated != package_text:
        PACKAGE_FILE.write_text(updated, encoding="utf-8")
        print(f"Updated {PACKAGE_FILE.relative_to(FLAKE_ROOT)} to {latest}")

    print("Validating package patches...")
    nix_build(PACKAGE_ATTR, no_link=True)


if __name__ == "__main__":
    main()
