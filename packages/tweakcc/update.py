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


def _flake_root(start: Path) -> Path:
    """Walk up from ``start`` until a directory containing ``flake.nix`` is found."""
    for parent in [start, *start.parents]:
        if (parent / "flake.nix").is_file():
            return parent
    msg = f"Could not find flake.nix above {start}"
    raise RuntimeError(msg)


FLAKE_ROOT = _flake_root(Path(__file__).resolve())
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_json,
    load_hashes,
    save_hashes,
)

REPO = "Piebald-AI/tweakcc"
BRANCH = "main"
HASHES_FILE = Path(__file__).parent / "hashes.json"


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
