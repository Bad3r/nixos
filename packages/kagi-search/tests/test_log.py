# Copyright (c) 2026 Bad3r
"""The private failure log."""

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
            with (
                unittest.mock.patch.object(log.os, "fstat", side_effect=OSError(5, "EIO")),
                unittest.mock.patch.object(
                    log.os, "close", side_effect=lambda d: (closed.append(d), real_close(d))
                ),
            ):
                log.FileLog(path)("entry")
            self.assertEqual(len(closed), 1)

    def test_state_root_follows_an_absolute_xdg_state_home(self) -> None:
        """A relative XDG_STATE_HOME is ignored, as the spec requires."""
        with unittest.mock.patch.dict(os.environ, {"XDG_STATE_HOME": "/s"}):
            self.assertEqual(log.state_root(), Path("/s/kagi-search"))
        with unittest.mock.patch.dict(os.environ, {"XDG_STATE_HOME": "rel"}):
            self.assertEqual(log.state_root(), Path.home() / ".local/state/kagi-search")
