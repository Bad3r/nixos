# Copyright (c) 2026 Bad3r
"""Copies between the host and sandboxes."""

import contextlib
import os
import resource
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import TYPE_CHECKING

from sbx import journal, windows
from sbx.config import remote_name
from sbx.errors import SbxError
from sbx.execution import MAX_STDIN, Execution
from sbx.fsutil import publish
from sbx.proc import run
from sbx.storage import Storage

if TYPE_CHECKING:
    from collections.abc import Sequence


WATCH_INTERVAL = 0.5


def _within(path: Path, roots: Sequence[Path]) -> bool:
    return any(path.is_relative_to(root) for root in roots)


def _allocated(path: Path) -> int:
    total = 0
    for parent, _dirs, files in os.walk(path):
        for file in files:
            with contextlib.suppress(FileNotFoundError):
                total += (Path(parent) / file).lstat().st_blocks * 512
    return total


def _strip_exec_bits(path: Path) -> None:
    """Drop execute, setuid, and setgid bits from every file under a copied-out path."""
    files = (
        [path]
        if not path.is_dir()
        else [Path(parent) / file for parent, _dirs, names in os.walk(path) for file in names]
    )
    for file in files:
        info = file.lstat()
        if stat.S_ISREG(info.st_mode):
            file.chmod(stat.S_IMODE(info.st_mode) & 0o666)


def guest_source(guest_path: str, *, on_windows: bool) -> PurePosixPath | PureWindowsPath:
    """Parse a guest path to copy out, which must name a file or directory."""
    source = windows.guest_path(guest_path) if on_windows else PurePosixPath(guest_path)
    if source.name in {"", ".", ".."}:
        msg = f"'{guest_path}' names no file or directory to copy out"
        raise SbxError(msg, code="invalid-argument")
    return source


class Transfer(Execution, Storage):
    """`sbx cp` in both directions, bounded by the disk cap."""

    def host_roots(self) -> list[Path]:
        """Return the host directories `cp` reads from and writes to."""
        roots = [Path.home() / "trees"]
        if tmpdir := os.environ.get("TMPDIR"):
            roots.append(Path(tmpdir))
        if checkout := self.checkout():
            roots.append(checkout)
        return [root.resolve() for root in roots if root.is_dir()]

    def checkout(self) -> Path | None:
        """Return the caller's git checkout, unless it is $HOME or holds it."""
        environment = {
            key: value for key, value in os.environ.items() if not key.startswith("GIT_")
        }
        result = subprocess.run(
            [self.settings.tools.git, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
            env=environment,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        toplevel = Path(result.stdout.strip()).resolve()
        # core.worktree can point the toplevel at any directory, such as $HOME.
        if not (toplevel / ".git").exists():
            return None
        home = Path.home().resolve()
        if toplevel == home or toplevel in home.parents:
            return None
        return toplevel

    def _denied(self, path: Path, roots: Sequence[Path]) -> SbxError:
        msg = f"{path} is outside the copy roots: {', '.join(map(str, roots))}"
        return SbxError(msg, code="path-denied")

    def _source(self, path: Path) -> Path:
        roots = self.host_roots()
        resolved = path.resolve(strict=True)
        if not _within(resolved, roots):
            raise self._denied(path, roots)
        if resolved.is_dir():
            for parent, dirs, files in os.walk(resolved):
                for entry in [*dirs, *files]:
                    candidate = Path(parent) / entry
                    if not candidate.is_symlink():
                        continue
                    # scp follows links, and a linked directory may link further out.
                    if candidate.is_dir():
                        msg = f"{candidate} links to a directory; copy its target instead"
                        raise SbxError(msg, code="path-denied")
                    if not _within(candidate.resolve(), roots):
                        msg = f"{candidate} links outside the copy roots"
                        raise SbxError(msg, code="path-denied")
        return resolved

    def read_input(self, value: str) -> bytes:
        """Read `--stdin`: the caller's stdin for -, else a file under the copy roots."""
        if value == "-":
            return sys.stdin.buffer.read(MAX_STDIN + 1)
        path = self._source(Path(value))
        if not path.is_file():
            msg = f"--stdin takes a file or -, not the directory {value}"
            raise SbxError(msg, code="invalid-argument")
        with path.open("rb") as handle:
            return handle.read(MAX_STDIN + 1)

    def _destination(self, path: Path, leaf: str) -> Path:
        """Return a host target that does not exist yet, under the copy roots."""
        roots = self.host_roots()
        resolved = path.resolve()
        if resolved.is_dir():
            resolved /= leaf
        if not resolved.parent.is_dir() or not _within(resolved.parent, roots):
            raise self._denied(path, roots)
        if os.path.lexists(resolved):
            msg = f"{resolved} exists; copies out never overwrite"
            raise SbxError(msg, code="exists")
        return resolved

    def _remote(self, argument: str) -> tuple[str, str] | None:
        name = remote_name(argument)
        if name is None:
            return None
        path = argument.partition(":")[2]
        if not path:
            msg = f"'{argument}' names no path inside the sandbox"
            raise SbxError(msg, code="invalid-argument")
        return name, path

    def copy(
        self, source: str, destination: str | None, *, token: str | None = None
    ) -> dict[str, object]:
        """Copy between the host and a sandbox over scp on vsock; with `token`, that creation."""
        remote_source = self._remote(source)
        remote_destination = None if destination is None else self._remote(destination)
        if (remote_source is None) == (remote_destination is None):
            msg = "exactly one side of cp names a sandbox as <name>:<path>"
            raise SbxError(msg, code="invalid-argument")
        if remote_destination is not None:
            name, guest_path = remote_destination
            local = self._source(Path(source))
            sandbox = self._running(name, token)
            journal.record(
                f"cp {local} {name}:{guest_path}", verb="cp", sandbox=name, session=self.session
            )
            if self.windows_base(sandbox.meta.base) is not None:
                guest = self.windows_guest(sandbox.domain.name)
                return {
                    "from": str(local),
                    "to": f"{name}:{windows.copy_in(guest, local, guest_path)}",
                }
            options = self._ssh_options(name, sandbox.domain)
            run(
                [
                    self.settings.tools.scp,
                    *options,
                    "-q",
                    "-r",
                    str(local),
                    f"root@sbx:{guest_path}",
                ]
            )
            return {"from": str(local), "to": f"{name}:{guest_path}"}
        if remote_source is None:
            msg = "cp needs a sandbox source"
            raise SbxError(msg, code="invalid-argument")
        name, guest_path = remote_source
        return self._copy_out(name, guest_path, destination, token)

    def _copy_out(
        self, name: str, guest_path: str, destination: str | None, token: str | None
    ) -> dict[str, object]:
        sandbox = self._running(name, token)
        on_windows = self.windows_base(sandbox.meta.base) is not None
        source = guest_source(guest_path, on_windows=on_windows)
        leaf = source.name
        xfer = self.paths.sandbox(name) / "xfer"
        if destination is None:
            target = xfer / leaf
            if os.path.lexists(target):
                msg = f"{target} exists; copies out never overwrite"
                raise SbxError(msg, code="exists")
        else:
            target = self._destination(Path(destination), leaf)
        budget = self._copy_budget()
        journal.record(
            f"cp {name}:{guest_path} {target}", verb="cp", sandbox=name, session=self.session
        )
        stage = xfer / f".stage-{secrets.token_hex(4)}"
        stage.mkdir(mode=0o700)
        try:
            staged = stage / leaf
            if not staged.resolve().is_relative_to(stage.resolve()):
                msg = f"'{guest_path}' leaves the transfer directory"
                raise SbxError(msg, code="path-denied")
            if isinstance(source, PureWindowsPath):
                guest = self.windows_guest(sandbox.domain.name)
                windows.copy_out(guest, source, stage, budget)
            else:
                options = self._ssh_options(name, sandbox.domain)
                argv = [self.settings.tools.scp, *options, "-q", "-r", f"root@sbx:{guest_path}"]
                self._bounded_transfer([*argv, str(staged)], stage, budget)
            _strip_exec_bits(staged)
            self.check_disk()
            publish(staged, target)
        finally:
            shutil.rmtree(stage, ignore_errors=True)
        return {"from": f"{name}:{guest_path}", "to": str(target)}

    def _copy_budget(self) -> int:
        """Return the bytes a copy out may write before it passes the cap or the floor."""
        self.paths.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        stats = os.statvfs(self.paths.root)
        free = stats.f_bavail * stats.f_frsize
        budget = min(
            self.settings.disk_cap_bytes - self._usage(), free - self.settings.min_free_bytes
        )
        if budget <= 0:
            msg = "no room for a copy out under the disk cap and the free-space floor"
            raise SbxError(msg, code="disk-full")
        return budget

    def _bounded_transfer(self, argv: Sequence[str], stage: Path, budget: int) -> None:
        """Run scp with each file capped by RLIMIT_FSIZE and the stage by a watchdog."""

        def limit() -> None:
            resource.setrlimit(resource.RLIMIT_FSIZE, (budget, budget))

        over = False
        with (
            tempfile.TemporaryFile() as errors,
            subprocess.Popen(
                argv,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=errors,
                preexec_fn=limit,  # noqa: PLW1509
            ) as process,
        ):
            while True:
                try:
                    process.wait(WATCH_INTERVAL)
                    break
                except subprocess.TimeoutExpired:
                    if _allocated(stage) > budget:
                        over = True
                        process.kill()
            errors.seek(0)
            detail = errors.read().decode(errors="replace").strip()
        if over or process.returncode == -signal.SIGXFSZ:
            msg = f"the copy passed its {budget >> 20}M budget under the disk cap and floor"
            raise SbxError(msg, code="disk-full")
        if process.returncode != 0:
            msg = f"scp exited {process.returncode}: {detail}"
            raise SbxError(msg, code="command-failed")
