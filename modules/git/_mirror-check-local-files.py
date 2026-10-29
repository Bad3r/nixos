# Copyright (c) 2026 Bad3r
"""Reject updates that would overwrite untracked or ignored local files."""

import subprocess
import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator


def _git_paths(repo: str, *args: str) -> set[bytes]:
    output = subprocess.check_output(["git", "-C", repo, *args, "-z"])
    return {path.rstrip(b"/") for path in output.split(b"\0") if path}


def _parents(path: bytes) -> Iterator[bytes]:
    while b"/" in path:
        path = path.rsplit(b"/", 1)[0]
        yield path


def main() -> int:
    """Check an upstream revision without changing the index or local files."""
    repo, revision = sys.argv[1:]
    # Without exclude options, ls-files includes ignored files. Git reset can
    # overwrite those even with --keep, so they need the same collision check.
    local = _git_paths(repo, "ls-files", "--others")
    if not local:
        return 0
    upstream = _git_paths(repo, "ls-tree", "-r", "--name-only", revision)
    upstream_dirs = {parent for path in upstream for parent in _parents(path)}
    conflicts = sorted(
        path
        for path in local
        if path in upstream
        or path in upstream_dirs
        or any(parent in upstream for parent in _parents(path))
    )
    for path in conflicts:
        print(f"refusing to overwrite local path {path!r}", file=sys.stderr)
    return int(bool(conflicts))


if __name__ == "__main__":
    sys.exit(main())
