# Copyright (c) 2026 Bad3r
"""Default profile lookup and the kagi_session snapshot."""

import shutil
import sqlite3
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from kagi_search import cookie

SCHEMA = """
create table moz_cookies (
  id integer primary key, originAttributes text not null default '', name text,
  value text, host text, lastAccessed integer
)
"""


def add_cookie(
    connection: sqlite3.Connection,
    value: str,
    *,
    host: str = ".kagi.com",
    origin: str = "",
    accessed: int = 1,
) -> None:
    """Insert a kagi_session cookie row and commit it."""
    connection.execute(
        "insert into moz_cookies (originAttributes, name, value, host, lastAccessed)"
        " values (?, 'kagi_session', ?, ?, ?)",
        (origin, value, host, accessed),
    )
    connection.commit()


class ProfileTest(unittest.TestCase):
    """Which profile profiles.ini names as the default."""

    def setUp(self) -> None:
        """Create an empty LibreWolf root."""
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)

    def write_ini(self, text: str) -> None:
        """Write profiles.ini into the root."""
        (self.root / "profiles.ini").write_text(text)

    def test_the_default_profile(self) -> None:
        """The profile marked Default=1 is chosen."""
        self.write_ini(
            "[General]\nStartWithLastProfile=1\n\n"
            "[Profile0]\nName=primary\nIsRelative=1\nPath=primary\nDefault=1\n\n"
            "[Profile1]\nName=work\nIsRelative=1\nPath=work\n"
        )
        self.assertEqual(cookie.default_profile(self.root), self.root / "primary")

    def test_default_1_wins_over_an_install_default(self) -> None:
        """Under MOZ_LEGACY_PROFILES, Default=1 overrides an Install section's Default."""
        self.write_ini(
            "[Install4F96D1932A9F858E]\nDefault=work\nLocked=1\n\n"
            "[Profile0]\nPath=primary\nDefault=1\n\n[Profile1]\nPath=work\n"
        )
        self.assertEqual(cookie.default_profile(self.root), self.root / "primary")

    def test_an_install_default_without_default_1(self) -> None:
        """An Install section's Default names the profile when none has Default=1."""
        self.write_ini(
            "[Install4F96D1932A9F858E]\nDefault=work\nLocked=1\n\n"
            "[Profile0]\nPath=primary\n\n[Profile1]\nPath=work\n"
        )
        self.assertEqual(cookie.default_profile(self.root), self.root / "work")

    def test_an_absolute_profile_path(self) -> None:
        """IsRelative=0 takes the path as written."""
        self.write_ini("[Profile0]\nIsRelative=0\nPath=/srv/profile\n")
        self.assertEqual(cookie.default_profile(self.root), Path("/srv/profile"))

    def test_no_profiles_ini(self) -> None:
        """A missing profiles.ini is a SessionError."""
        with self.assertRaisesRegex(cookie.SessionError, "no LibreWolf profiles.ini"):
            cookie.default_profile(self.root)


class SessionTest(unittest.TestCase):
    """Reading kagi_session from a snapshot of cookies.sqlite."""

    def setUp(self) -> None:
        """Create a profile with an empty cookie table."""
        self.profile = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.profile)
        self.db = self.profile / "cookies.sqlite"
        self.connection = sqlite3.connect(self.db)
        self.addCleanup(self.connection.close)
        self.connection.execute(SCHEMA)

    def test_the_first_party_session_most_recently_used(self) -> None:
        """Container and recency rank cookies; partitioned and foreign ones are ignored."""
        add_cookie(self.connection, "old", accessed=1)
        add_cookie(self.connection, "new", accessed=2)
        add_cookie(self.connection, "container", origin="^userContextId=1", accessed=3)
        add_cookie(self.connection, "third-party", origin="^partitionKey=x", accessed=4)
        add_cookie(self.connection, "other", host="example.com", accessed=5)
        self.assertEqual(cookie.read_session(self.profile), "new")

    def test_a_session_only_in_the_live_wal(self) -> None:
        """A cookie not yet checkpointed out of the WAL is found."""
        self.connection.execute("pragma journal_mode = wal")
        self.connection.execute("pragma wal_autocheckpoint = 0")
        add_cookie(self.connection, "in-wal")
        self.assertTrue(self.db.with_name("cookies.sqlite-wal").stat().st_size > 0)
        self.assertEqual(cookie.read_session(self.profile), "in-wal")

    def test_a_change_during_the_copy_is_retried(self) -> None:
        """A database change between the copies restarts the snapshot."""
        add_cookie(self.connection, "token")
        real_copy = shutil.copyfile
        calls: list[str] = []

        def copy_then_touch(source: Path, target: Path) -> Path:
            calls.append(str(source))
            result = real_copy(source, target)
            if len(calls) == 1:
                add_cookie(self.connection, "token", host="example.com")
            return result

        with unittest.mock.patch.object(cookie.shutil, "copyfile", copy_then_touch):
            self.assertEqual(cookie.read_session(self.profile), "token")
        self.assertEqual(len(calls), 2)

    def test_a_wal_removed_during_the_copy_is_retried(self) -> None:
        """A WAL that LibreWolf removes after it was seen restarts the snapshot."""
        self.connection.execute("pragma journal_mode = wal")
        self.connection.execute("pragma wal_autocheckpoint = 0")
        add_cookie(self.connection, "in-wal")
        real_copy = shutil.copyfile
        calls: list[str] = []

        def checkpoint_then_copy(source: Path, target: Path) -> Path:
            calls.append(Path(source).name)
            if len(calls) == 1:
                self.connection.execute("pragma wal_checkpoint(truncate)")
                self.connection.execute("pragma journal_mode = delete")
            return real_copy(source, target)

        with unittest.mock.patch.object(cookie.shutil, "copyfile", checkpoint_then_copy):
            self.assertEqual(cookie.read_session(self.profile), "in-wal")
        self.assertEqual(calls, ["cookies.sqlite-wal", "cookies.sqlite"])

    def test_a_database_removed_during_the_copy_is_no_database(self) -> None:
        """A database removed mid-copy reports a missing database, not a retry loop."""
        add_cookie(self.connection, "token")

        def remove_then_copy(source: Path, _target: Path) -> Path:
            self.db.unlink()
            raise FileNotFoundError(source)

        with (
            unittest.mock.patch.object(cookie.shutil, "copyfile", remove_then_copy),
            self.assertRaisesRegex(cookie.SessionError, "no readable LibreWolf cookie database"),
        ):
            cookie.read_session(self.profile)

    def test_an_unreadable_copy_is_a_session_error(self) -> None:
        """A database SQLite cannot read is a SessionError, not a traceback."""
        self.connection.close()
        self.db.write_bytes(b"not a database" * 512)
        with self.assertRaisesRegex(cookie.SessionError, "cannot read the copy"):
            cookie.read_session(self.profile)

    def test_a_copy_refused_is_a_session_error(self) -> None:
        """A copy the file system refuses is a SessionError, not a traceback."""
        add_cookie(self.connection, "token")
        refused = unittest.mock.Mock(side_effect=PermissionError(13, "Permission denied"))
        with (
            unittest.mock.patch.object(cookie.shutil, "copyfile", refused),
            self.assertRaisesRegex(cookie.SessionError, "cannot copy"),
        ):
            cookie.read_session(self.profile)

    def test_no_session_says_to_sign_in(self) -> None:
        """No cookie tells the user to sign in."""
        with self.assertRaisesRegex(cookie.SessionError, "sign in to kagi.com in LibreWolf"):
            cookie.read_session(self.profile)

    def test_no_database(self) -> None:
        """A missing database is a SessionError."""
        with self.assertRaisesRegex(cookie.SessionError, "no readable LibreWolf cookie database"):
            cookie.read_session(self.profile / "missing")
