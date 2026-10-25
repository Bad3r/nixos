# Copyright (c) 2026 Bad3r
"""Sandboxes across host sleep, for the host sleep hook rather than agents.

`pause` and `save` attach only to a session daemon that already runs, since no
sandbox runs without it, so they never bring one up. They record what they act
on under `$XDG_RUNTIME_DIR/sbx/`; `resume` and `restore` bring back only
recorded sandboxes. Every phase exits 1 on any failure, and the hook decides
what that means: a failed pause only warns, a failed save aborts hibernation.
"""

import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING

from sbx import journal
from sbx.core import GIB, Backend, Sandbox, Sandboxes, SbxError

if TYPE_CHECKING:
    from collections.abc import Callable
    from types import FrameType

PHASES = ("pause", "resume", "save", "restore")
MIB = 1 << 20
# How long a phase waits for another sbx command to release the state lock.
LOCK_WAIT = 30
# How long guest agents may stay unconnected after a resume or restore, shared by all.
AGENT_WAIT = 15
# The whole save phase, below the hook's 300 s cap so sbx aborts its own save job.
SAVE_BUDGET = 270
# How long an aborted save job may take to wind down.
ABORT_WAIT = 20
# How long restore waits for saves still running, such as one the hook gave up on.
JOB_WAIT = 120


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

    def __init__(
        self,
        sandboxes: Sandboxes,
        state: Path,
        attach: Callable[[], Backend],
        *,
        as_json: bool,
    ) -> None:
        """Bind the sandboxes, the record directory, and a connect that never starts a daemon."""
        self.sandboxes = sandboxes
        self.state = state
        self.attach = attach
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
        return self.actions, 1 if self.failed else 0

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

    def _attached(self) -> bool:
        """Use the running session daemon; return False when none runs."""
        settings = self.sandboxes.settings
        active = [settings.tools.systemctl, "--user", "is-active", "--quiet", settings.unit]
        if subprocess.run(active, check=False).returncode != 0:
            return False
        try:
            self.sandboxes.adopt(self.attach())
        except SbxError as failure:
            if failure.code == "no-daemon":
                return False
            raise
        return True

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

    def _host_synced(self) -> bool:
        show = [self.sandboxes.settings.tools.timedatectl, "show", "-p", "NTPSynchronized"]
        result = subprocess.run([*show, "--value"], capture_output=True, text=True, check=False)
        return result.stdout.strip() == "yes"

    def _sync_clocks(self, names: list[str]) -> None:
        """Set each running sandbox's clock to the host's, as `domtime --now` does."""
        if not names:
            return
        # Right after resume the host clock may still be the RTC's, hours off on songbird.
        if not self._host_synced():
            warn("the host clock is not NTP-synchronized, so sandbox clocks keep their time")
            return
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
                    # A stale clock is not a failed phase, as for system guests.
                    warn(f"{name} keeps a stale clock: {failure}")
                else:
                    self._emit(name, "synced")
                break

    # Phases

    def pause(self) -> None:
        """Suspend every running sandbox."""
        if not self._attached():
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

    def _save_one(
        self, backend: Backend, sandbox: Sandbox, deadline: float, stop: threading.Event
    ) -> None:
        """Managed-save one sandbox, aborting the job at the deadline or on SIGTERM."""
        done = threading.Event()
        failures: list[SbxError] = []

        def work() -> None:
            try:
                backend.managed_save(sandbox.domain.name)
            except SbxError as failure:
                failures.append(failure)
            finally:
                done.set()

        threading.Thread(target=work, daemon=True).start()
        while not done.wait(0.2):
            if not stop.is_set() and time.monotonic() < deadline:
                continue
            why = "sbx was stopped" if stop.is_set() else f"the phase ran past {SAVE_BUDGET} s"
            try:
                # The guest runs on once its save job is aborted.
                backend.abort_job(sandbox.domain.name)
            except SbxError as failure:
                warn(f"{sandbox.name}: the save job was not aborted: {failure}")
            done.wait(ABORT_WAIT)
            msg = f"{sandbox.name} failed to save, so the host did not sleep: {why}"
            raise SbxError(msg, code="save-aborted")
        if failures:
            msg = f"{sandbox.name} failed to save, so the host did not sleep: {failures[0]}"
            raise SbxError(msg, code=failures[0].code)

    def save(self) -> None:
        """Destroy sandboxes past their TTL, then managed-save the rest; stop at a failure."""
        deadline = time.monotonic() + SAVE_BUDGET
        if not self._attached():
            return
        for name in self.sandboxes.destroy_where(mine=False, expired=True, timeout=LOCK_WAIT):
            self._emit(name, "destroyed")
        stop = threading.Event()

        def stopped(_signum: int, _frame: FrameType | None) -> None:
            stop.set()

        previous = signal.signal(signal.SIGTERM, stopped)
        try:
            with self.sandboxes.locked(LOCK_WAIT):
                backend = self.sandboxes.backend()
                keep = sorted(
                    (sandbox for sandbox in self.sandboxes.owned() if sandbox.domain.active),
                    key=lambda item: item.name,
                )
                # Nothing to save means no image, so the floor cannot be at stake.
                if not keep:
                    return
                self._check_room(keep)
                for sandbox in keep:
                    self._note("saved", sandbox.name)
                    self._save_one(backend, sandbox, deadline, stop)
                    self._emit(sandbox.name, "saved")
        finally:
            signal.signal(signal.SIGTERM, previous)

    def _still_saving(self, backend: Backend, sandbox: Sandbox, deadline: float) -> bool:
        """Wait until a sandbox's job ends or the deadline passes; return whether it runs on."""
        domain = sandbox.domain.name
        while backend.job_active(domain) and time.monotonic() < deadline:
            time.sleep(1)
        return backend.job_active(domain)

    def _restore_one(self, backend: Backend, sandbox: Sandbox) -> bool:
        """Start one sandbox from its managed save; return False when it should be retried."""
        if not sandbox.domain.managed_save:
            self._fail("restore", f"{sandbox.name} has no managed save, so it stays shut off")
            return True
        try:
            backend.restore(sandbox.domain.name)
        except SbxError as failure:
            self._fail("restore", f"{sandbox.name} stays saved: {failure}")
            return False
        self._emit(sandbox.name, "restored")
        return True

    def restore(self) -> None:
        """Restore every recorded sandbox and resync clocks; expiry is left to `sbx gc`."""
        names = self._recorded("saved")
        if not names:
            return
        # Restored guests join the daemon's cgroup, so it must run in the slice.
        backend = self.sandboxes.backend(require_slice=True)
        with self.sandboxes.locked(LOCK_WAIT):
            sandboxes = self._by_name()
            job_deadline = time.monotonic() + JOB_WAIT
            unresolved: list[str] = []
            for name in names:
                sandbox = sandboxes.get(name)
                if sandbox is not None and sandbox.domain.active:
                    if self._still_saving(backend, sandbox, job_deadline):
                        self._fail("restore", f"{name} is still saving")
                        unresolved.append(name)
                        continue
                    sandbox = self._by_name().get(name)
                # Gone, or running: its save was aborted, or someone started it.
                if sandbox is None or sandbox.domain.active:
                    continue
                if not self._restore_one(backend, sandbox):
                    unresolved.append(name)
            restored = [item["sandbox"] for item in self.actions if item["action"] == "restored"]
            self._sync_clocks(restored)
            record = self.state / "saved"
            if unresolved:
                record.write_text("".join(f"{name}\n" for name in unresolved))
            else:
                record.unlink(missing_ok=True)
