#!/usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3
# Copyright (c) 2026 Bad3r

"""Update script for chromium-search, which upstream publishes without releases."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import cast

PACKAGE_NAME = "chromium-search"
OWNER = "jclay"
REPO = "chromium-search"
SHA_PATTERN = re.compile(r"[0-9a-f]{40}")
DATE_PATTERN = re.compile(r"(\d{4}-\d{2}-\d{2})T")


SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
HASHES_FILE = PACKAGE_DIR / "hashes.json"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_url_hash,
    fetch_json,
    load_hashes,
    save_hashes,
)


def latest_commit() -> tuple[str, str]:
    """Resolve the default branch head to its commit and committer date."""
    data = fetch_json(f"https://api.github.com/repos/{OWNER}/{REPO}/commits/HEAD")
    if not isinstance(data, dict):
        msg = f"Expected a commit object, got {type(data)}"
        raise TypeError(msg)
    rev = data.get("sha")
    commit = data.get("commit")
    committer = commit.get("committer") if isinstance(commit, dict) else None
    stamp = committer.get("date") if isinstance(committer, dict) else None
    if not isinstance(rev, str) or SHA_PATTERN.fullmatch(rev) is None:
        msg = f"Invalid commit sha for {OWNER}/{REPO}: {rev!r}"
        raise ValueError(msg)
    match = DATE_PATTERN.match(stamp) if isinstance(stamp, str) else None
    if match is None:
        msg = f"Invalid commit date for {OWNER}/{REPO}: {stamp!r}"
        raise ValueError(msg)
    return rev, match.group(1)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check-release",
        action="store_true",
        help="validate commit metadata without fetching the archive hash",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="recalculate the hash even when the commit is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Pin chromium-search to the latest commit of its default branch."""
    args = parse_args()
    data = load_hashes(HASHES_FILE)
    current = cast("str", data["rev"])
    rev, date = latest_commit()

    print(f"Current: {current}")
    print(f"Latest:  {rev}")

    if args.check_release:
        print("Commit metadata is valid")
        return

    if current == rev and not args.force:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = calculate_url_hash(
        f"https://github.com/{OWNER}/{REPO}/archive/{rev}.tar.gz",
        unpack=True,
    )
    save_hashes(
        HASHES_FILE,
        {"version": f"0-unstable-{date}", "rev": rev, "srcHash": src_hash},
    )
    print(f"Updated {HASHES_FILE.relative_to(FLAKE_ROOT)} to {rev}")


if __name__ == "__main__":
    main()
