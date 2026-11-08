#!/usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3
# Copyright (c) 2026 Bad3r

"""Update the JNI headers used to build the LIEF Ghidra extension."""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
import tempfile
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, "lief-ghidra")
PINS_FILE = PACKAGE_DIR / "hashes.json"

from updater import calculate_url_hash, fetch_json, load_hashes  # noqa: E402

REPO = "google/jni-bind"
VERSION_PATTERN = re.compile(r"Release-([0-9]+\.[0-9]+\.[0-9]+)")
SHA_PATTERN = re.compile(r"[0-9a-f]{40}")


def latest_pin() -> dict[str, str]:
    """Resolve the latest stable release to an immutable source commit."""
    release = fetch_json(f"https://api.github.com/repos/{REPO}/releases/latest")
    if not isinstance(release, dict):
        msg = "Expected a jni-bind release object"
        raise TypeError(msg)
    if release.get("draft") is not False or release.get("prerelease") is not False:
        msg = "Refusing a draft or prerelease jni-bind release"
        raise ValueError(msg)
    tag = release.get("tag_name")
    match = VERSION_PATTERN.fullmatch(tag) if isinstance(tag, str) else None
    if match is None:
        msg = f"Invalid jni-bind release tag: {tag!r}"
        raise ValueError(msg)
    commit = fetch_json(f"https://api.github.com/repos/{REPO}/commits/{tag}")
    rev = commit.get("sha") if isinstance(commit, dict) else None
    if not isinstance(rev, str) or SHA_PATTERN.fullmatch(rev) is None:
        msg = f"Invalid source commit for jni-bind {tag}"
        raise ValueError(msg)
    return {"version": match.group(1), "rev": rev}


def write_pins(text: str) -> None:
    """Replace the pin file after fetching and hashing have succeeded."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=PACKAGE_DIR, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(text)
        temporary.chmod(PINS_FILE.stat().st_mode & 0o777)
        temporary.replace(PINS_FILE)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> None:
    """Refresh only jni-bind; LIEF and Ghidra follow the flake's nixpkgs pin."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="recalculate an unchanged source hash")
    parser.add_argument("--dry-run", action="store_true", help="show the update without writing")
    parser.add_argument(
        "--check-release",
        action="store_true",
        help="validate release metadata without downloading source archives",
    )
    args = parser.parse_args()
    before = PINS_FILE.read_text(encoding="utf-8")
    pins = load_hashes(PINS_FILE)
    current = pins["jni-bind"]
    latest = latest_pin()
    print(
        f"jni-bind: {current['version']} ({current['rev']}) -> "
        f"{latest['version']} ({latest['rev']})"
    )
    print("LIEF plugin sources and library follow the same pinned nixpkgs LIEF package")
    if args.check_release:
        print("Release metadata is valid")
        return
    if latest == {"version": current["version"], "rev": current["rev"]} and not args.force:
        print("Already up to date")
        return
    latest["hash"] = calculate_url_hash(
        f"https://github.com/{REPO}/archive/{latest['rev']}.tar.gz",
        unpack=True,
    )
    pins["jni-bind"] = latest
    after = json.dumps(pins, indent="\t") + "\n"
    if before == after:
        print("Already up to date")
        return
    if args.dry_run:
        name = str(PINS_FILE.relative_to(FLAKE_ROOT))
        print(
            "".join(
                difflib.unified_diff(
                    before.splitlines(keepends=True),
                    after.splitlines(keepends=True),
                    name,
                    name,
                )
            )
        )
        return
    if PINS_FILE.read_text(encoding="utf-8") != before:
        msg = f"{PINS_FILE} changed during the update; refusing to overwrite it"
        raise RuntimeError(msg)
    write_pins(after)
    print(f"Updated {PINS_FILE.relative_to(FLAKE_ROOT)}")


if __name__ == "__main__":
    main()
