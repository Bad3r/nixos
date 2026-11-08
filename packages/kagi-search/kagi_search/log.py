# Copyright (c) 2026 Bad3r
"""The private state directory and the failure logs kept in it."""

from __future__ import annotations

import contextlib
import datetime as dt
import fcntl
import os
import time
from pathlib import Path

DIRECTORY_MODE = 0o700
FILE_MODE = 0o600
LOG_FLAGS = os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC
LOG_MAX_BYTES = 5 * 1024 * 1024
OPEN_ATTEMPTS = 5
LOCK_WAIT_SECONDS = 2.0
LOCK_POLL_SECONDS = 0.01


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


def _lock(descriptor: int) -> bool:
    """Take the file's exclusive lock, giving up after LOCK_WAIT_SECONDS."""
    deadline = time.monotonic() + LOCK_WAIT_SECONDS
    while True:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if time.monotonic() >= deadline:
                return False
            time.sleep(LOCK_POLL_SECONDS)
        else:
            return True


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
            # Writers append to and rotate only the file still at path, under its lock;
            # one that finds its file rotated away opens the new one and tries again.
            # A lock held past LOCK_WAIT_SECONDS is skipped: the entry is appended and
            # rotation waits for a later writer.
            for _ in range(OPEN_ATTEMPTS):
                # Opening first makes a log that already existed private before it rotates.
                descriptor = self._open()
                try:
                    locked = _lock(descriptor)
                    held = os.fstat(descriptor)
                    if not self._is_current(held):
                        continue
                    if locked and held.st_size > LOG_MAX_BYTES:
                        self.path.replace(self.path.with_name(f"{self.path.name}.1"))
                        continue
                    os.write(descriptor, entry)
                    return
                finally:
                    os.close(descriptor)

    def _is_current(self, held: os.stat_result) -> bool:
        """Tell whether the held file is still the one at path."""
        try:
            current = self.path.stat(follow_symlinks=False)
        except FileNotFoundError:
            return False
        return (held.st_dev, held.st_ino) == (current.st_dev, current.st_ino)

    def _open(self) -> int:
        """Open the log for appending, private whether or not it existed before."""
        descriptor = os.open(self.path, LOG_FLAGS, FILE_MODE)
        try:
            os.fchmod(descriptor, FILE_MODE)
        except BaseException:
            os.close(descriptor)
            raise
        return descriptor
