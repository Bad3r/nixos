#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for tweakcc.

Upstream Piebald-AI/tweakcc does tag releases (v4.x), but this package
tracks the unstable HEAD of ``main`` to follow ongoing work that has not
yet been released. The pin is therefore a commit SHA plus the commit
date encoded as ``unstable-YYYY-MM-DD``.
"""

import sys
from pathlib import Path
from typing import Any, cast

PACKAGE_NAME = "tweakcc"
REPO = "Piebald-AI/tweakcc"
BRANCH = "main"


SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_json,
    load_hashes,
    save_hashes,
)

HASHES_FILE = PACKAGE_DIR / "hashes.json"


def latest_main_commit() -> dict[str, Any]:
    """Fetch the latest commit on ``main`` from the GitHub API."""
    url = f"https://api.github.com/repos/{REPO}/commits/{BRANCH}"
    return cast("dict[str, Any]", fetch_json(url))


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
    src_hash = calculate_url_hash(
        f"https://github.com/{REPO}/archive/{sha}.tar.gz",
        unpack=True,
    )

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
