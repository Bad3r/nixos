# Copyright (c) 2026 Bad3r
"""The private state directory and the failure logs kept in it."""

from __future__ import annotations

import contextlib
import datetime as dt
import os
from pathlib import Path

DIRECTORY_MODE = 0o700
FILE_MODE = 0o600
LOG_FLAGS = os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC
LOG_MAX_BYTES = 5 * 1024 * 1024


def state_root() -> Path:
    """Return kagi-search's directory under XDG_STATE_HOME."""
    base = os.environ.get("XDG_STATE_HOME", "")
    root = Path(base) if base and Path(base).is_absolute() else Path.home() / ".local" / "state"
    return root / "kagi-search"


def private_directory(*directories: Path) -> None:
    """Create the directories and make each one private, leaving their parents alone."""
    for directory in directories:
        directory.mkdir(mode=DIRECTORY_MODE, parents=True, exist_ok=True)
        directory.chmod(DIRECTORY_MODE)


class FileLog:
    """Append timestamped entries to a private log file, rotating it past LOG_MAX_BYTES."""

    def __init__(self, path: Path) -> None:
        """Log to the file at path."""
        self.path = path

    def __call__(self, text: str) -> None:
        """Append one entry; a log that cannot be written must not fail the call."""
        stamp = dt.datetime.now(dt.UTC).isoformat(timespec="seconds")
        entry = f"{stamp} {text.rstrip()}\n".encode(errors="replace")
        with contextlib.suppress(OSError):
            private_directory(self.path.parent)
            if self.path.exists() and self.path.stat().st_size > LOG_MAX_BYTES:
                self.path.replace(self.path.with_name(f"{self.path.name}.1"))
            descriptor = os.open(self.path, LOG_FLAGS, FILE_MODE)
            try:
                os.fchmod(descriptor, FILE_MODE)
                os.write(descriptor, entry)
            finally:
                os.close(descriptor)
