# Copyright (c) 2026 Bad3r
"""Run directories: their disk usage and their removal."""

import contextlib
import os
import shutil
import stat
import sys
from pathlib import Path

from sbx import journal
from sbx.context import Context
from sbx.errors import SbxError
from sbx.model import CREATION_FILE, DOMAIN_PREFIX, GIB, SHARED
from sbx.net import revoke_grants


def _reopen_shared(directory: Path) -> None:
    """Give the owner search and read on every directory under shared again.

    A running guest may swap a directory for a link at any time, so each one is
    opened without following links and changed through its descriptor.
    """
    # One open descriptor per level, with the names left to visit in it.
    levels: list[tuple[int | None, list[str]]] = [(None, [str(directory / SHARED)])]
    try:
        while levels:
            parent, names = levels[-1]
            if not names:
                levels.pop()
                if parent is not None:
                    os.close(parent)
                continue
            try:
                handle = os.open(
                    names.pop(), os.O_PATH | os.O_NOFOLLOW | os.O_DIRECTORY, dir_fd=parent
                )
            except FileNotFoundError, NotADirectoryError:
                continue
            try:
                info = os.fstat(handle)
                if not stat.S_ISDIR(info.st_mode):
                    continue
                proc = Path(f"/proc/self/fd/{handle}")
                if info.st_mode & stat.S_IRWXU != stat.S_IRWXU:
                    proc.chmod(stat.S_IMODE(info.st_mode) | stat.S_IRWXU)
                listing = os.open(proc, os.O_RDONLY | os.O_DIRECTORY)
            finally:
                os.close(handle)
            try:
                children = [e.name for e in os.scandir(listing) if e.is_dir(follow_symlinks=False)]
            except OSError:
                os.close(listing)
                raise
            levels.append((listing, children))
    finally:
        for parent, _names in levels:
            if parent is not None:
                os.close(parent)


def _remove_run_directory(directory: Path) -> None:
    """Remove a run directory after reopening the shared directories a guest closed."""
    _reopen_shared(directory)
    shutil.rmtree(directory)


class Storage(Context):
    """Disk usage of run directories and the removal of sandboxes."""

    def _usage(self) -> int:
        """Bytes under every run directory; a directory that cannot be read raises."""

        def unreadable(error: OSError) -> None:
            if not isinstance(error, FileNotFoundError):
                raise error

        total = 0
        for directory in self.paths.sandbox_dirs():
            _reopen_shared(directory)
            for parent, _dirs, files in os.walk(directory, onerror=unreadable):
                for file in files:
                    with contextlib.suppress(FileNotFoundError):
                        total += (Path(parent) / file).lstat().st_blocks * 512
        return total

    def disk_problem(self, reserve: int = 0) -> str | None:
        """Say why usage plus `reserve` passes the free-space floor or the cap, if it does."""
        self.paths.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        stats = os.statvfs(self.paths.root)
        free = stats.f_bavail * stats.f_frsize
        if free < self.settings.min_free_bytes:
            return (
                f"{self.paths.root} has {free // GIB}G free, "
                f"below the {self.settings.min_free_bytes // GIB}G floor"
            )
        try:
            used = self._usage()
        except OSError as error:
            return f"sandbox usage cannot be measured, so the cap counts as passed: {error}"
        if used + reserve > self.settings.disk_cap_bytes:
            return (
                f"sandboxes use {used // GIB}G and need {reserve // GIB}G more of the "
                f"{self.settings.disk_cap_bytes // GIB}G cap; destroy some or run `sbx gc`"
            )
        return None

    def check_disk(self, reserve: int = 0) -> None:
        """Refuse below the free-space floor or when usage plus `reserve` passes the cap."""
        problem = self.disk_problem(reserve)
        if problem is not None:
            raise SbxError(problem, code="disk-full")

    def _discard(self, name: str, token: str | None = None) -> None:
        """Remove a sandbox's domain, directory, and grants; the caller holds the lock.

        With a token, only a domain and directory that carry it go, so a later
        sandbox of the same name survives the cleanup of an earlier one.
        """
        sandbox = self._owned(name)
        removed = False
        address = None
        if sandbox is not None and (token is None or sandbox.meta.token == token):
            address = self.address(sandbox)
            self.backend().remove(DOMAIN_PREFIX + name)
            removed = True
        directory = self.paths.sandbox(name)
        try:
            if directory.is_dir() and (token is None or self._carries(directory, token)):
                removed = True
                _remove_run_directory(directory)
        finally:
            if removed:
                self._revoke_grants(name, address)

    @staticmethod
    def _carries(directory: Path, token: str) -> bool:
        try:
            return (directory / CREATION_FILE).read_text() == token
        except FileNotFoundError:
            return False

    @staticmethod
    def _revoke_grants(name: str, address: str | None) -> None:
        """The sandbox is gone either way; a grant the helper keeps is reported, not fatal."""
        try:
            revoke_grants(name, address)
        except SbxError as error:
            journal.record(f"grants of {name} stay live: {error}", code=error.code, sandbox=name)
            print(f"sbx: grants of {name} stay live: {error}", file=sys.stderr)
