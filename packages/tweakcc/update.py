#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for tweakcc.

Upstream Piebald-AI/tweakcc does tag releases (v4.x), but this package
tracks the unstable HEAD of ``main`` to follow ongoing work that has not
yet been released. The pin is therefore a commit SHA plus the commit
date encoded as ``unstable-YYYY-MM-DD``.
"""

import json
import sys
from pathlib import Path
from typing import Any, cast

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_dependency_hash,
    fetch_json,
    load_hashes,
    save_hashes,
)
from updater.nix import nix_command

REPO = "Piebald-AI/tweakcc"
BRANCH = "main"
HASHES_FILE = Path(__file__).parent / "hashes.json"


def latest_main_commit() -> dict[str, Any]:
    """Fetch the latest commit on ``main`` from the GitHub API."""
    url = f"https://api.github.com/repos/{REPO}/commits/{BRANCH}"
    return cast("dict[str, Any]", fetch_json(url))


def prefetch_github(rev: str) -> str:
    """Prefetch a fetchFromGitHub-compatible tarball and return its SRI hash."""
    url = f"https://github.com/{REPO}/archive/{rev}.tar.gz"
    result = nix_command(
        ["store", "prefetch-file", "--unpack", "--hash-type", "sha256", "--json", url],
    )
    return cast("str", json.loads(result.stdout)["hash"])


def main() -> None:
    """Update tweakcc to the latest commit on ``main``."""
    data = load_hashes(HASHES_FILE)
    commit = latest_main_commit()
    sha = cast("str", commit["sha"])
    date = cast("str", commit["commit"]["author"]["date"])[:10]

    print(f"Current: {data['srcRev'][:12]} ({data['version']})")
    print(f"Latest:  {sha[:12]} (unstable-{date})")

    if sha == data["srcRev"]:
        print("Already up to date")
        return

    print("Calculating source hash...")
    src_hash = prefetch_github(sha)

    new_data: dict[str, Any] = {
        "version": f"unstable-{date}",
        "srcRev": sha,
        "srcHash": src_hash,
        "pnpmDepsHash": data.get("pnpmDepsHash", ""),
    }

    new_data["pnpmDepsHash"] = calculate_dependency_hash(
        ".#tweakcc",
        "pnpmDepsHash",
        HASHES_FILE,
        new_data,
    )
    save_hashes(HASHES_FILE, new_data)
    print(f"Updated to {new_data['version']} ({sha[:12]})")


if __name__ == "__main__":
    main()
