# Copyright (c) 2026 Bad3r
"""The kagi_session cookie of a LibreWolf profile."""

from __future__ import annotations

import configparser
import os
import shutil
import sqlite3
import tempfile
import time
from pathlib import Path
from typing import override

ATTEMPTS = 5
RETRY_STEP_SECONDS = 0.05


class SessionError(Exception):
    """No usable Kagi session in the profile."""


class _CaseSensitiveParser(configparser.ConfigParser):
    """INI parser that keeps option names as written."""

    @override
    def optionxform(self, optionstr: str) -> str:
        """Return the option name unchanged."""
        return optionstr


def librewolf_root() -> Path:
    """Return LibreWolf's profile root directory."""
    return Path.home() / ".librewolf"


def default_profile(root: Path) -> Path:
    """Return the profile LibreWolf starts with, as its profiles.ini names it."""
    ini = root / "profiles.ini"
    parser = _CaseSensitiveParser(interpolation=None)
    if not parser.read(ini):
        msg = f"no LibreWolf profiles.ini at {ini}"
        raise SessionError(msg)
    profiles = [parser[name] for name in parser.sections() if name.startswith("Profile")]
    installs = [parser[name] for name in parser.sections() if name.startswith("Install")]
    path: str | None = next((s["Default"] for s in installs if s.get("Default")), None)
    if path is not None:
        return root / path
    chosen = next((s for s in profiles if s.get("Default") == "1"), None)
    if chosen is None and len(profiles) == 1:
        chosen = profiles[0]
    if chosen is None or not chosen.get("Path"):
        msg = f"{ini} names no default profile"
        raise SessionError(msg)
    location = Path(chosen["Path"])
    return root / location if chosen.get("IsRelative", "1") == "1" else location


def _state(path: Path) -> tuple[int, int, int] | None:
    try:
        stat = path.stat()
    except FileNotFoundError:
        return None
    return (stat.st_ino, stat.st_size, stat.st_mtime_ns)


def _snapshot(db: Path, into: Path) -> Path:
    """Copy the database and its WAL into a consistent pair.

    LibreWolf holds cookies.sqlite in exclusive locking mode, so SQLite cannot
    read it in place. The WAL goes first: a checkpoint between the two copies
    then leaves an older but consistent pair. Changes during the copy retry it.
    """
    wal = db.with_name(f"{db.name}-wal")
    copy = into / db.name
    for attempt in range(ATTEMPTS):
        before = (_state(db), _state(wal))
        copy_wal = copy.with_name(f"{copy.name}-wal")
        copy_wal.unlink(missing_ok=True)
        try:
            if before[1] is not None:
                shutil.copyfile(wal, copy_wal)
            shutil.copyfile(db, copy)
        except FileNotFoundError:
            if not db.exists():
                msg = f"no readable LibreWolf cookie database at {db}"
                raise SessionError(msg) from None
            continue
        if (_state(db), _state(wal)) == before:
            return copy
        time.sleep(RETRY_STEP_SECONDS * (attempt + 1))
    msg = f"{db} kept changing while it was copied; try again"
    raise SessionError(msg)


def read_session(profile: Path) -> str:
    """Return the profile's kagi_session cookie value."""
    db = profile / "cookies.sqlite"
    if not os.access(db, os.R_OK):
        msg = f"no readable LibreWolf cookie database at {db}"
        raise SessionError(msg)
    with tempfile.TemporaryDirectory(prefix="kagi-search-") as tmp:
        copy = _snapshot(db, Path(tmp))
        connection = sqlite3.connect(copy)
        try:
            row: tuple[str] | None = connection.execute(
                """
                select value from moz_cookies
                where name = 'kagi_session'
                  and host in ('kagi.com', '.kagi.com')
                  and originAttributes not like '%partitionKey=%'
                order by originAttributes = '' desc, lastAccessed desc
                limit 1
                """
            ).fetchone()
        finally:
            connection.close()
    if row is None or not row[0]:
        msg = f"no kagi_session cookie in {db}; sign in to kagi.com in LibreWolf"
        raise SessionError(msg)
    return row[0]
