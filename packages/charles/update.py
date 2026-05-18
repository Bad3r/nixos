#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for Charles."""

from __future__ import annotations

import argparse
import re
import sys
import urllib.request
from pathlib import Path


PACKAGE_NAME = "charles"
VERSION_HISTORY_URL = "https://www.charlesproxy.com/documentation/version-history/"
USER_AGENT = "Mozilla/5.0"


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

from updater import calculate_url_hash, fetch_text  # noqa: E402


def release_url(version: str) -> str:
    """Return the Charles Linux x64 archive URL."""
    return (
        "https://www.charlesproxy.com/assets/release/"
        f"{version}/charles-proxy-{version}_x86_64.tar.gz"
    )


def latest_stable_version() -> str:
    """Fetch the newest non-beta Charles version from the version history."""
    text = fetch_text(VERSION_HISTORY_URL, user_agent=USER_AGENT)
    for match in re.finditer(r"<h4>Version ([^<]+)</h4>", text):
        version = match.group(1).strip()
        if re.fullmatch(r"\d+(?:\.\d+)*", version):
            return version

    msg = f"Could not find a stable Charles version in {VERSION_HISTORY_URL}"
    raise RuntimeError(msg)


def current_version(text: str) -> str:
    """Read the packaged version from default.nix."""
    match = re.search(r'^  version = "([^"]+)";$', text, flags=re.MULTILINE)
    if match is None:
        msg = f"Could not find {PACKAGE_NAME} version in {PACKAGE_FILE}"
        raise RuntimeError(msg)
    return match.group(1)


def check_release_url(version: str) -> None:
    """Check that the expected Linux x64 archive exists."""
    request = urllib.request.Request(release_url(version), method="HEAD")
    request.add_header("User-Agent", USER_AGENT)
    with urllib.request.urlopen(request, timeout=30):
        return


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
            r"(?P<prefix>  src = fetchurl \{\n"
            r'    url = "https://www\.charlesproxy\.com/assets/release/'
            r'\$\{version\}/charles-proxy-\$\{version\}_x86_64\.tar\.gz";\n'
            r"    curlOptsList = \[\n"
            r'      "--user-agent"\n'
            r'      "Mozilla/5\.0"\n'
            r"    \];\n"
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
    """Update Charles to the latest stable vendor release."""
    args = parse_args()
    package_text = PACKAGE_FILE.read_text(encoding="utf-8")
    current = current_version(package_text)
    latest = latest_stable_version()
    check_release_url(latest)

    print(f"Current: {current}")
    print(f"Latest:  {latest}")
    print(f"Archive: {release_url(latest)}")

    if args.check_release:
        print("Release metadata is valid")
        return

    if current == latest and not args.force:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = calculate_url_hash(
        release_url(latest),
        headers={"User-Agent": USER_AGENT},
    )
    updated = updated_package_text(latest, src_hash)

    if updated == package_text:
        print(f"{PACKAGE_FILE.relative_to(FLAKE_ROOT)} already matches {latest}")
        return

    PACKAGE_FILE.write_text(updated, encoding="utf-8")
    print(f"Updated {PACKAGE_FILE.relative_to(FLAKE_ROOT)} to {latest}")


if __name__ == "__main__":
    main()
