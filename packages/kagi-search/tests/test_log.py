# Copyright (c) 2026 Bad3r
"""The private failure log."""

import fcntl
import os
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from kagi_search import log


class FileLogTest(unittest.TestCase):
    """Entries, rotation, and where the state directory lives."""

    def test_rotation_keeps_one_previous_file(self) -> None:
        """A log past LOG_MAX_BYTES moves to .1 before the next entry."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.log"
            path.write_bytes(b"o" * (log.LOG_MAX_BYTES + 1))
            log.FileLog(path)("new")
            self.assertEqual(path.with_name("x.log.1").stat().st_size, log.LOG_MAX_BYTES + 1)
            self.assertTrue(path.read_text().endswith(" new\n"))

    def test_an_existing_log_is_made_private(self) -> None:
        """A log created with wider permissions is narrowed on the next entry."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.log"
            path.write_text("")
            path.chmod(0o644)
            log.FileLog(path)("entry")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_a_rotated_log_is_private(self) -> None:
        """A wide, oversized log is made private before it moves to .1."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.log"
            path.write_bytes(b"o" * (log.LOG_MAX_BYTES + 1))
            path.chmod(0o644)
            log.FileLog(path)("new")
            self.assertEqual(path.with_name("x.log.1").stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_a_failed_check_closes_the_log(self) -> None:
        """A descriptor opened for an entry is closed even when its stat fails."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.log"
            closed: list[int] = []
            real_close = os.close

            def close(descriptor: int) -> None:
                closed.append(descriptor)
                real_close(descriptor)

            with (
                unittest.mock.patch.object(log.os, "fstat", side_effect=OSError(5, "EIO")),
                unittest.mock.patch.object(log.os, "close", side_effect=close),
            ):
                log.FileLog(path)("entry")
            self.assertEqual(len(closed), 1)

    def test_a_log_rotated_by_another_writer_is_not_rotated_again(self) -> None:
        """A writer still holding the log another one rotated keeps .1 and writes the new log."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.log"
            path.write_bytes(b"o" * (log.LOG_MAX_BYTES + 1))
            writer = log.FileLog(path)
            real_open = writer._open  # noqa: SLF001  # pyright: ignore[reportPrivateUsage]
            stale = real_open()
            log.FileLog(path)("first")
            with unittest.mock.patch.object(writer, "_open", side_effect=[stale, real_open()]):
                writer("second")
            self.assertEqual(path.with_name("x.log.1").stat().st_size, log.LOG_MAX_BYTES + 1)
            lines = path.read_text().splitlines()
            self.assertEqual([line.split(" ", 1)[1] for line in lines], ["first", "second"])

    def test_a_file_rotated_before_the_write_is_not_written(self) -> None:
        """An entry never lands in a file another writer rotated after it was opened."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.log"
            path.write_bytes(b"o" * (log.LOG_MAX_BYTES + 1))
            writer = log.FileLog(path)
            real_open = writer._open  # noqa: SLF001  # pyright: ignore[reportPrivateUsage]
            opens = 0

            def racing_open() -> int:
                nonlocal opens
                opens += 1
                descriptor = real_open()
                if opens == 2:  # noqa: PLR2004 - the open after this writer's own rotation
                    # Another writer rotates the fresh file away and starts the next one.
                    path.replace(path.with_name("x.log.1"))
                    path.write_text("")
                return descriptor

            with unittest.mock.patch.object(writer, "_open", side_effect=racing_open):
                writer("entry")
            self.assertNotIn("entry", path.with_name("x.log.1").read_text())
            self.assertTrue(path.read_text().endswith(" entry\n"))

    def test_a_held_lock_delays_the_entry_without_blocking(self) -> None:
        """A lock held past the wait still gets the entry appended, unrotated."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.log"
            path.write_bytes(b"o" * (log.LOG_MAX_BYTES + 1))
            holder = os.open(path, os.O_RDONLY)
            try:
                fcntl.flock(holder, fcntl.LOCK_EX)
                with unittest.mock.patch.object(log, "LOCK_WAIT_SECONDS", 0.05):
                    log.FileLog(path)("entry")
            finally:
                os.close(holder)
            self.assertFalse(path.with_name("x.log.1").exists())
            self.assertTrue(path.read_bytes().endswith(b" entry\n"))

    def test_state_root_follows_an_absolute_xdg_state_home(self) -> None:
        """A relative XDG_STATE_HOME is ignored, as the spec requires."""
        with unittest.mock.patch.dict(os.environ, {"XDG_STATE_HOME": "/s"}):
            self.assertEqual(log.state_root(), Path("/s/kagi-search"))
        with unittest.mock.patch.dict(os.environ, {"XDG_STATE_HOME": "rel"}):
            self.assertEqual(log.state_root(), Path.home() / ".local/state/kagi-search")
