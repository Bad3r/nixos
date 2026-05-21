#!/usr/bin/env nix
#! nix shell nixpkgs#python3 nixpkgs#nix --command python3
"""Update script for Charles."""

from __future__ import annotations

import argparse
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

PACKAGE_NAME = "charles"
VERSION_HISTORY_URL = "https://www.charlesproxy.com/documentation/version-history/"
USER_AGENT = "Mozilla/5.0"

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
PACKAGE_FILE = PACKAGE_DIR / "default.nix"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import calculate_url_hash, fetch_text  # noqa: E402


def release_url(version: str) -> str:
    """Return the Charles Linux x64 archive URL."""
    return (
        "https://www.charlesproxy.com/assets/release/"
        f"{version}/charles-proxy-{version}_x86_64.tar.gz"
    )


def require_https_url(url: str) -> None:
    """Reject unexpected archive URL schemes before a HEAD request."""
    scheme = urllib.parse.urlparse(url).scheme.lower()
    if scheme != "https":
        msg = f"Refusing to check non-HTTPS archive URL: {url}"
        raise ValueError(msg)


def latest_stable_version() -> str:
    """Fetch the newest non-beta Charles version from the version history."""
    text = fetch_text(VERSION_HISTORY_URL, user_agent=USER_AGENT)
    versions: list[str] = []
    for match in re.finditer(r"<h4>Version ([^<]+)</h4>", text):
        version = match.group(1).strip()
        if re.fullmatch(r"\d+(?:\.\d+)*", version):
            versions.append(version)

    if versions:
        return max(versions, key=lambda version: tuple(int(x) for x in version.split(".")))

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
    url = release_url(version)
    require_https_url(url)
    request = urllib.request.Request(url, method="HEAD")  # noqa: S310
    request.add_header("User-Agent", USER_AGENT)
    with urllib.request.urlopen(request, timeout=30):  # noqa: S310
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

    print(f"Current: {current}")
    print(f"Latest:  {latest}")
    print(f"Archive: {release_url(latest)}")

    if current == latest and not args.force and not args.check_release:
        print("Already up to date")
        return

    check_release_url(latest)

    if args.check_release:
        print("Release metadata is valid")
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
