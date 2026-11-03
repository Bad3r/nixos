# Copyright (c) 2026 Bad3r
"""Reject updates that would overwrite untracked or ignored local files."""

import os
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator

GITLINK = b"160000"


def _git_paths(repo: str, *args: str) -> set[bytes]:
    output = subprocess.check_output(["git", "-C", repo, *args, "-z"])
    return {path.rstrip(b"/") for path in output.split(b"\0") if path}


def _tree(repo: str, revision: str) -> dict[bytes, bytes]:
    output = subprocess.check_output(
        ["git", "-C", repo, "ls-tree", "-r", "-z", "--format=%(objectmode) %(path)", revision]
    )
    entries = (entry.split(b" ", 1) for entry in output.split(b"\0") if entry)
    return {path: mode for mode, path in entries}


def _parents(path: bytes) -> Iterator[bytes]:
    while b"/" in path:
        path = path.rsplit(b"/", 1)[0]
        yield path


def _populated(repo: str, path: bytes) -> bool:
    directory = Path(repo) / os.fsdecode(path)
    return directory.is_dir() and any(directory.iterdir())


def main() -> int:
    """Check a revision without changing the index or local files."""
    repo, revision = sys.argv[1:]
    # A stash restores HEAD before the reset checks out the revision.
    head = _tree(repo, "HEAD")
    target = _tree(repo, revision)
    trees = [head, target]

    # ls-files skips submodule directories, and a revision without the gitlink
    # replaces whatever was checked out or left there.
    conflicts = {
        path
        for path, mode in head.items()
        if mode == GITLINK and target.get(path) != GITLINK and _populated(repo, path)
    }

    # Without exclude options, ls-files includes ignored files. Git reset can
    # overwrite those even with --keep, so they need the same collision check.
    local = _git_paths(repo, "ls-files", "--others")
    if local:
        upstream = {path for tree in trees for path in tree}
        # A gitlink only replaces a path itself; files under it stay in place.
        upstream_files = {path for tree in trees for path, mode in tree.items() if mode != GITLINK}
        upstream_dirs = {parent for path in upstream for parent in _parents(path)}
        conflicts.update(
            path
            for path in local
            if path in upstream
            or path in upstream_dirs
            or any(parent in upstream_files for parent in _parents(path))
        )

    for path in sorted(conflicts):
        print(f"refusing to overwrite local path {os.fsdecode(path)!r}", file=sys.stderr)
    return int(bool(conflicts))


if __name__ == "__main__":
    sys.exit(main())
