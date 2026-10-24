# Copyright (c) 2026 Bad3r
"""Sandboxes across host sleep, for the host sleep hook rather than agents.

`pause` and `save` act only while the session daemon unit is active, since no
sandbox runs without it, so the hook never brings up a daemon. They record what
they act on under `$XDG_RUNTIME_DIR/sbx/`; `resume` and `restore` bring back
only recorded sandboxes and drop the record once done. `pause` and `resume`
exit 0 whatever fails; `save` and `restore` exit 1 on any failure, so a failed
save aborts the host's sleep transition.
"""

import os
import subprocess
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

from sbx import journal
from sbx.core import GIB, Sandbox, Sandboxes, SbxError

if TYPE_CHECKING:
    from collections.abc import Callable

PHASES = ("pause", "resume", "save", "restore")
MIB = 1 << 20
# How long a phase waits for another sbx command to release the state lock.
LOCK_WAIT = 30
# How long guest agents may stay unconnected after a resume or restore, shared by all.
AGENT_WAIT = 15


def state_dir() -> Path:
    """Return where the phases keep their records."""
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / "sbx"


def warn(message: str) -> None:
    """Print one journal line at warning priority."""
    print(f"<4>warning: {message}", file=sys.stderr, flush=True)


def error(message: str) -> None:
    """Print one journal line at error priority."""
    print(f"<3>error: {message}", file=sys.stderr, flush=True)


class Sleep:
    """One host sleep phase over every sandbox of the calling user."""

    def __init__(self, sandboxes: Sandboxes, state: Path, *, as_json: bool) -> None:
        """Bind the sandboxes and the record directory."""
        self.sandboxes = sandboxes
        self.state = state
        self.as_json = as_json
        self.actions: list[dict[str, str]] = []
        self.failed = False

    def run(self, phase: str) -> tuple[list[dict[str, str]], int]:
        """Run one phase; return what it did and its exit code."""
        phases: dict[str, Callable[[], None]] = {
            "pause": self.pause,
            "resume": self.resume,
            "save": self.save,
            "restore": self.restore,
        }
        try:
            phases[phase]()
        except (SbxError, OSError) as failure:
            self._fail(phase, f"{phase} stopped: {failure}")
        return self.actions, 1 if self.failed and phase in {"save", "restore"} else 0

    # Plumbing

    def _emit(self, name: str, action: str) -> None:
        self.actions.append({"sandbox": name, "action": action})
        if not self.as_json:
            print(f"sandbox={name} action={action}", flush=True)

    def _fail(self, phase: str, message: str) -> None:
        self.failed = True
        if phase in {"save", "restore"}:
            error(message)
        else:
            warn(message)
        journal.record(f"sleep {phase}: {message}", verb="sleep", code="sleep-failed")

    def _daemon_active(self) -> bool:
        settings = self.sandboxes.settings
        active = [settings.tools.systemctl, "--user", "is-active", "--quiet", settings.unit]
        return subprocess.run(active, check=False).returncode == 0

    def _note(self, record: str, name: str) -> None:
        """Record a sandbox before acting on it; appended, so names never brought back stay."""
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.state / record).open("a") as records:
            records.write(f"{name}\n")

    def _recorded(self, record: str) -> list[str]:
        try:
            lines = (self.state / record).read_text().splitlines()
        except FileNotFoundError:
            return []
        return list(dict.fromkeys(line for line in lines if line))

    def _by_name(self) -> dict[str, Sandbox]:
        return {sandbox.name: sandbox for sandbox in self.sandboxes.owned()}

    def _destroy_expired(self) -> None:
        """Remove every sandbox past its TTL; it takes the state lock itself."""
        for name in self.sandboxes.destroy_where(mine=False, expired=True, timeout=LOCK_WAIT):
            self._emit(name, "destroyed")

    def _sync_clocks(self, names: list[str]) -> None:
        """Set each running sandbox's clock to the host's, as `domtime --now` does."""
        backend = self.sandboxes.backend()
        running = self._by_name()
        deadline = time.monotonic() + AGENT_WAIT
        for name in names:
            sandbox = running.get(name)
            # A sandbox saved while paused comes back paused.
            if sandbox is None or sandbox.domain.state != "running":
                continue
            while True:
                try:
                    backend.set_time(sandbox.domain.name)
                except SbxError as failure:
                    if failure.code == "agent-unresponsive" and time.monotonic() < deadline:
                        time.sleep(1)
                        continue
                    warn(f"{name} keeps a stale clock: {failure}")
                else:
                    self._emit(name, "synced")
                break

    # Phases

    def pause(self) -> None:
        """Suspend every running sandbox."""
        if not self._daemon_active():
            return
        with self.sandboxes.locked(LOCK_WAIT):
            backend = self.sandboxes.backend()
            for sandbox in sorted(self.sandboxes.owned(), key=lambda item: item.name):
                if sandbox.domain.state != "running":
                    continue
                self._note("paused", sandbox.name)
                try:
                    backend.suspend(sandbox.domain.name)
                except SbxError as failure:
                    self._fail("pause", f"{sandbox.name} kept running through suspend: {failure}")
                else:
                    self._emit(sandbox.name, "paused")

    def resume(self) -> None:
        """Resume the sandboxes `pause` recorded, then resync their clocks."""
        names = self._recorded("paused")
        if not names:
            return
        with self.sandboxes.locked(LOCK_WAIT):
            backend = self.sandboxes.backend()
            sandboxes = self._by_name()
            resumed: list[str] = []
            for name in names:
                sandbox = sandboxes.get(name)
                # Gone, or resumed or saved by someone else.
                if sandbox is None or sandbox.domain.state != "paused":
                    continue
                try:
                    backend.resume(sandbox.domain.name)
                except SbxError as failure:
                    self._fail("resume", f"{name} stays paused: {failure}")
                else:
                    self._emit(name, "resumed")
                    resumed.append(name)
            self._sync_clocks(resumed)
            (self.state / "paused").unlink(missing_ok=True)

    def _check_room(self, sandboxes: list[Sandbox]) -> None:
        """Refuse when the save images could push the save filesystem below the floor."""
        save_dir = self.sandboxes.paths.config / "libvirt" / "qemu" / "save"
        existing = next(path for path in [save_dir, *save_dir.parents] if path.exists())
        stats = os.statvfs(existing)
        free = stats.f_bavail * stats.f_frsize
        # Device state adds a few MiB per image, which the floor absorbs.
        need = sum(sandbox.domain.memory_mib for sandbox in sandboxes) * MIB
        floor = self.sandboxes.settings.min_free_bytes
        if free - need < floor:
            msg = (
                f"saving {len(sandboxes)} sandboxes takes up to {need // MIB}M on {existing}, "
                f"which has {free // GIB}G free and keeps a {floor // GIB}G floor"
            )
            raise SbxError(msg, code="disk-full")

    def save(self) -> None:
        """Destroy sandboxes past their TTL, then managed-save the rest; stop at a failure."""
        if not self._daemon_active():
            return
        self._destroy_expired()
        with self.sandboxes.locked(LOCK_WAIT):
            backend = self.sandboxes.backend()
            keep = sorted(
                (sandbox for sandbox in self.sandboxes.owned() if sandbox.domain.active),
                key=lambda item: item.name,
            )
            self._check_room(keep)
            for sandbox in keep:
                self._note("saved", sandbox.name)
                try:
                    backend.managed_save(sandbox.domain.name)
                except SbxError as failure:
                    msg = f"{sandbox.name} failed to save, so the host did not sleep: {failure}"
                    raise SbxError(msg, code=failure.code) from failure
                self._emit(sandbox.name, "saved")

    def restore(self) -> None:
        """Restore the saved sandboxes within their TTL, resync clocks, destroy the rest."""
        names = self._recorded("saved")
        if not names:
            return
        # Restored guests join the daemon's cgroup, so it must run in the slice.
        backend = self.sandboxes.backend(require_slice=True)
        self._destroy_expired()
        with self.sandboxes.locked(LOCK_WAIT):
            sandboxes = self._by_name()
            restored: list[str] = []
            for name in names:
                sandbox = sandboxes.get(name)
                # Destroyed, or started by someone else.
                if sandbox is None or sandbox.domain.active:
                    continue
                if not sandbox.domain.managed_save:
                    self._fail("restore", f"{name} has no managed save, so it stays shut off")
                    continue
                try:
                    backend.restore(sandbox.domain.name)
                except SbxError as failure:
                    self._fail("restore", f"{name} stays saved: {failure}")
                else:
                    self._emit(name, "restored")
                    restored.append(name)
            self._sync_clocks(restored)
            (self.state / "saved").unlink(missing_ok=True)
