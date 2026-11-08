#!/usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3
# Copyright (c) 2026 Bad3r

"""Pin DDisasm main and its pretty printer to immutable source snapshots."""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, "ddisasm")
PINS_FILE = PACKAGE_DIR / "hashes.json"

from updater import calculate_url_hash, fetch_json, fetch_text, load_hashes  # noqa: E402

BRANCHES = {"ddisasm": "main", "gtirb-pprinter": "master"}
SHA_PATTERN = re.compile(r"[0-9a-f]{40}")


def latest_pin(repo: str, branch: str) -> dict[str, str]:
    """Resolve the branch once and read version metadata at that exact commit."""
    data = fetch_json(f"https://api.github.com/repos/GrammaTech/{repo}/commits/{branch}")
    if not isinstance(data, dict):
        msg = f"Expected commit metadata for {repo}/{branch}"
        raise TypeError(msg)
    rev = data.get("sha")
    if not isinstance(rev, str) or SHA_PATTERN.fullmatch(rev) is None:
        msg = f"Invalid commit SHA for {repo}/{branch}"
        raise ValueError(msg)
    commit = data.get("commit")
    committer = commit.get("committer") if isinstance(commit, dict) else None
    timestamp = committer.get("date") if isinstance(committer, dict) else None
    if not isinstance(timestamp, str):
        msg = f"Missing commit timestamp for {repo}/{rev}"
        raise TypeError(msg)
    date = datetime.fromisoformat(timestamp).date().isoformat()
    text = fetch_text(f"https://raw.githubusercontent.com/GrammaTech/{repo}/{rev}/version.txt")
    parts: list[str] = []
    for component in ("MAJOR", "MINOR", "PATCH"):
        matches = re.findall(rf"^VERSION_{component}\s+([0-9]+)\s*$", text, re.MULTILINE)
        if len(matches) != 1:
            msg = f"Invalid VERSION_{component} in {repo}/{rev}/version.txt"
            raise ValueError(msg)
        parts.append(matches[0])
    return {"version": f"{'.'.join(parts)}-unstable-{date}", "rev": rev}


def write_pins(text: str) -> None:
    """Replace the pin file atomically after every download has succeeded."""
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
    """Refresh branch snapshots without changing the fixed compatibility dependencies."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="recalculate unchanged source hashes")
    parser.add_argument("--dry-run", action="store_true", help="show the update without writing")
    parser.add_argument(
        "--check-release",
        action="store_true",
        help="check branch metadata without downloading source archives",
    )
    args = parser.parse_args()
    before = PINS_FILE.read_text(encoding="utf-8")
    pins = load_hashes(PINS_FILE)
    changed = False
    for repo, branch in BRANCHES.items():
        latest = latest_pin(repo, branch)
        current = pins[repo]
        print(f"{repo}/{branch}: {current['rev']} -> {latest['rev']}")
        if args.check_release:
            continue
        if latest["rev"] == current["rev"] and not args.force:
            continue
        latest["hash"] = calculate_url_hash(
            f"https://github.com/GrammaTech/{repo}/archive/{latest['rev']}.tar.gz",
            unpack=True,
        )
        pins[repo] = latest
        changed = True
    if args.check_release:
        print("Branch metadata is valid")
        return
    after = json.dumps(pins, indent=2) + "\n"
    if not changed or before == after:
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
    # Do not replace edits made while upstream metadata and archives were downloading.
    if PINS_FILE.read_text(encoding="utf-8") != before:
        msg = f"{PINS_FILE} changed during the update; refusing to overwrite it"
        raise RuntimeError(msg)
    write_pins(after)
    print(f"Updated {PINS_FILE.relative_to(FLAKE_ROOT)}")


if __name__ == "__main__":
    main()
