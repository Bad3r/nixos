#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for wappalyzer-next."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


PACKAGE_NAME = "wappalyzer-next"
OWNER = "s0md3v"
REPO = "wappalyzer-next"


def _flake_root(start: Path) -> Path | None:
    """Walk up from ``start`` until this checkout's flake root is found."""
    for parent in [start, *start.parents]:
        if (
            (parent / "flake.nix").is_file()
            and (parent / "scripts" / "updater").is_dir()
            and (parent / "packages" / PACKAGE_NAME / "default.nix").is_file()
        ):
            return parent
    return None


def _checkout_root() -> Path:
    """Find the editable checkout from either cwd or the script path."""
    starts = [
        Path.cwd().resolve(),
        Path(__file__).resolve().parent,
    ]
    for start in starts:
        root = _flake_root(start)
        if root is not None:
            return root

    msg = (
        "Could not find the nixos checkout root. Run this updater from the "
        "repository checkout, or execute the checkout copy under "
        f"packages/{PACKAGE_NAME}/."
    )
    raise RuntimeError(msg)


FLAKE_ROOT = _checkout_root()
PACKAGE_FILE = FLAKE_ROOT / "packages" / PACKAGE_NAME / "default.nix"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import calculate_url_hash, fetch_github_latest_tag_version  # noqa: E402


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
            r'    owner = "s0md3v";\n'
            r'    repo = "wappalyzer-next";\n'
            r"    tag = version;\n"
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
    """Update wappalyzer-next to the latest stable GitHub tag."""
    args = parse_args()
    package_text = PACKAGE_FILE.read_text(encoding="utf-8")
    current = current_version(package_text)
    latest = fetch_github_latest_tag_version(OWNER, REPO, prefix="")

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
        f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/{latest}.tar.gz",
        unpack=True,
    )
    updated = updated_package_text(latest, src_hash)

    if updated == package_text:
        print(f"{PACKAGE_FILE.relative_to(FLAKE_ROOT)} already matches {latest}")
        return

    PACKAGE_FILE.write_text(updated, encoding="utf-8")
    print(f"Updated {PACKAGE_FILE.relative_to(FLAKE_ROOT)} to {latest}")


if __name__ == "__main__":
    main()
