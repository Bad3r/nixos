# Copyright (c) 2026 Bad3r
"""Host sleep hook for guests on `qemu:///system` and sbx sandboxes.

`pause` suspends running guests before host suspend, and `save` managed-saves active
guests before hibernation; each records the guests it acts on, and only `save` exits
non-zero, which aborts the sleep transition. `wake` runs after the sleep unit: it
resumes and restores the recorded guests, then resyncs their clocks. It tells each
active graphical session about every guest that failed a phase.

With `--sbx`, each phase also runs `sbx sleep` as every user logind lists. sbx keeps
its own records, and its pause and save act only while the user's sbx daemon unit
is active, so the hook never brings up a session daemon.
"""

import argparse
import contextlib
import fcntl
import json
import os
import pwd
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, TextIO

import libvirt

if TYPE_CHECKING:
    from collections.abc import Iterator

STATE_DIR = Path("/run/workloads-vm-sleep")
PAUSED = STATE_DIR / "paused"
SAVED = STATE_DIR / "saved"
FAILURES = STATE_DIR / "failures"
# Users whose sandboxes a pre phase handed to `sbx sleep`.
SESSIONS = STATE_DIR / "sessions"
RECORDS = (PAUSED, SAVED, FAILURES, SESSIONS)
# Held by a pre phase while it acts, and by wake from its claim through restore and resume.
LOCK = STATE_DIR / "lock"
# How long wake waits for running sleep units and the lock.
CLAIM_WAIT = 600
# How long a guest agent may stay unconnected after resume, shared by all guests.
AGENT_WAIT = 15
AGENT_CHANNEL = "devices/channel/target[@name='org.qemu.guest_agent.0']"
# How long one `sbx sleep` phase may run for one user.
SESSION_WAIT = 300


def log(message: str) -> None:
    """Print one journal line."""
    print(message, flush=True)


def warn(message: str) -> None:
    """Print one journal line at warning priority."""
    print(f"<4>warning: {message}", flush=True)


def fail(failures: list[str], message: str) -> None:
    """Log a guest failure and keep it for the wake notification."""
    warn(message)
    failures.append(message)


class SaveError(Exception):
    """A guest failed its managed save."""


@dataclass(frozen=True)
class Sessions:
    """Runs `sbx sleep` as each user."""

    sbx: str
    runuser: str

    @staticmethod
    def users() -> list[str]:
        """Return the users that have a user manager."""
        listing = ["loginctl", "list-users", "--json=short"]
        output = subprocess.run(listing, check=True, capture_output=True, text=True).stdout
        return sorted({user["user"] for user in json.loads(output)})

    def run(self, user: str, phase: str) -> str | None:
        """Run one phase as `user`; return why it failed, or None."""
        try:
            uid = pwd.getpwnam(user).pw_uid
            env = {"PATH": os.environ.get("PATH", ""), "XDG_RUNTIME_DIR": f"/run/user/{uid}"}
            command = [self.runuser, "-u", user, "--", self.sbx, "sleep", phase]
            with subprocess.Popen(command, env=env) as process:
                try:
                    code = process.wait(SESSION_WAIT)
                except subprocess.TimeoutExpired:
                    # runuser passes SIGTERM on to sbx.
                    process.terminate()
                    try:
                        process.wait(10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                    return f"sbx sleep {phase} ran past {SESSION_WAIT} s"
        except (KeyError, OSError) as error:
            return f"sbx sleep {phase} did not run: {error}"
        return None if code == 0 else f"sbx sleep {phase} exited {code}"


def by_name(conn: libvirt.virConnect, flags: int) -> list[libvirt.virDomain]:
    """List domains matching `flags`, sorted by name."""
    return sorted(conn.listAllDomains(flags), key=lambda domain: domain.name())


def record(records: TextIO, domain: libvirt.virDomain) -> None:
    """Record a domain before acting on it."""
    records.write(f"{domain.UUIDString()}\n")
    records.flush()


def pause(conn: libvirt.virConnect, records: TextIO, failures: list[str]) -> None:
    """Pause every running guest."""
    for domain in by_name(conn, libvirt.VIR_CONNECT_LIST_DOMAINS_RUNNING):
        record(records, domain)
        try:
            domain.suspend()
        except libvirt.libvirtError as error:
            fail(failures, f"{domain.name()} kept running through suspend: {error}")
        else:
            log(f"paused {domain.name()}")


def save(conn: libvirt.virConnect, records: TextIO, _failures: list[str]) -> None:
    """Managed-save every active guest; the first failure raises."""
    for domain in by_name(conn, libvirt.VIR_CONNECT_LIST_DOMAINS_ACTIVE):
        record(records, domain)
        log(f"saving {domain.name()}")
        try:
            domain.managedSave()
        except libvirt.libvirtError as error:
            msg = f"{domain.name()} failed to save, so the host did not sleep: {error}"
            raise SaveError(msg) from error
        log(f"saved {domain.name()}")


def recorded(conn: libvirt.virConnect, uuids: list[str]) -> list[libvirt.virDomain]:
    """Return the recorded domains that still exist."""
    domains: list[libvirt.virDomain] = []
    for uuid in uuids:
        try:
            domains.append(conn.lookupByUUIDString(uuid))
        except libvirt.libvirtError as error:
            warn(f"recorded guest {uuid}: {error}")
    return domains


def resume(domains: list[libvirt.virDomain], failures: list[str]) -> list[libvirt.virDomain]:
    """Resume the guests that are still paused."""
    resumed: list[libvirt.virDomain] = []
    for domain in domains:
        try:
            if domain.state()[0] != libvirt.VIR_DOMAIN_PAUSED:
                continue
            domain.resume()
        except libvirt.libvirtError as error:
            fail(failures, f"{domain.name()} stays paused: {error}")
        else:
            log(f"resumed {domain.name()}")
            resumed.append(domain)
    return resumed


def restore(domains: list[libvirt.virDomain], failures: list[str]) -> list[libvirt.virDomain]:
    """Start the guests that are shut off with a managed save."""
    restored: list[libvirt.virDomain] = []
    for domain in domains:
        try:
            # Active means its save failed or someone started it.
            if domain.isActive():
                continue
            if not domain.hasManagedSaveImage():
                fail(failures, f"{domain.name()} has no managed save, so it stays shut off")
                continue
            domain.create()
        except libvirt.libvirtError as error:
            fail(failures, f"{domain.name()} stays saved: {error}")
        else:
            log(f"restored {domain.name()}")
            restored.append(domain)
    return restored


def has_agent(domain: libvirt.virDomain) -> bool:
    """Return whether a domain has a QEMU guest agent channel."""
    root = ET.fromstring(domain.XMLDesc())  # noqa: S314
    return root.find(AGENT_CHANNEL) is not None


def sync_clocks(domains: list[libvirt.virDomain]) -> None:
    """Set each running guest's clock to the host's through its guest agent."""
    deadline = time.monotonic() + AGENT_WAIT
    for domain in domains:
        try:
            # A guest saved while paused is restored paused.
            if domain.state()[0] != libvirt.VIR_DOMAIN_RUNNING or not has_agent(domain):
                continue
        except libvirt.libvirtError as error:
            warn(f"{domain.name()} keeps a stale clock: {error}")
            continue
        while True:
            now = time.time_ns()
            try:
                domain.setTime({"seconds": now // 10**9, "nseconds": now % 10**9})
            except libvirt.libvirtError as error:
                unconnected = error.get_error_code() == libvirt.VIR_ERR_AGENT_UNRESPONSIVE
                if unconnected and time.monotonic() < deadline:
                    time.sleep(1)
                    continue
                warn(f"{domain.name()} keeps a stale clock: {error}")
            else:
                log(f"synced the clock of {domain.name()}")
            break


@contextlib.contextmanager
def locked(deadline: float | None = None) -> Iterator[None]:
    """Hold the state directory lock, waiting at most until `deadline`."""
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    with LOCK.open("w") as lock:
        while deadline is not None:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    msg = f"no lock on {LOCK} within {CLAIM_WAIT} s"
                    raise TimeoutError(msg) from None
                time.sleep(1)
        else:
            fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def append(path: Path, lines: list[str]) -> None:
    """Add lines to a record that wake has not claimed yet."""
    with path.open("a") as records:
        records.writelines(f"{line}\n" for line in lines)


def claimed(path: Path) -> Path:
    """Return where wake keeps a record until its batch is done."""
    return path.with_name(f"{path.name}.claimed")


def claim(path: Path) -> list[str]:
    """Move a record onto its claimed copy, so a later pre phase starts a new one."""
    with contextlib.suppress(FileNotFoundError):
        append(claimed(path), path.read_text().splitlines())
        path.unlink()
    try:
        return list(dict.fromkeys(claimed(path).read_text().splitlines()))
    except FileNotFoundError:
        return []


Batch = tuple[list[str], list[str], list[str], list[str]]


@contextlib.contextmanager
def claimed_batch(jobs: list[str]) -> Iterator[Batch | None]:
    """Hold the lock over the claimed records, or None when none are left.

    The claimed copies are deleted only when the block finishes without raising.
    """
    deadline = time.monotonic() + CLAIM_WAIT
    while True:
        with locked(deadline):
            # A running sleep unit's records belong to the wake its stop queues.
            if not subprocess.run(jobs, check=True, capture_output=True, text=True).stdout:
                batch = claim(PAUSED), claim(SAVED), claim(FAILURES), claim(SESSIONS)
                yield batch if any(batch) else None
                for path in RECORDS:
                    claimed(path).unlink(missing_ok=True)
                return
        if time.monotonic() >= deadline:
            msg = f"sleep units still running after {CLAIM_WAIT} s"
            raise TimeoutError(msg)
        time.sleep(1)


def graphical_users() -> set[int]:
    """Return the uids that own an active graphical session."""
    listing = ["loginctl", "list-sessions", "--no-legend"]
    sessions = subprocess.run(listing, check=True, capture_output=True, text=True).stdout
    uids: set[int] = set()
    for line in sessions.splitlines():
        show = ["loginctl", "show-session", line.split()[0], "-pType", "-pActive", "-pUser"]
        output = subprocess.run(show, check=True, capture_output=True, text=True).stdout
        props = dict(prop.split("=", 1) for prop in output.splitlines() if "=" in prop)
        if props.get("Type") in {"x11", "wayland"} and props.get("Active") == "yes":
            uids.add(int(props["User"]))
    return uids


def notify(failures: list[str]) -> None:
    """Show the failures in each active graphical session; a miss only logs."""
    try:
        uids = graphical_users()
    except (OSError, subprocess.CalledProcessError) as error:
        warn(f"no notification sent, the sessions are unknown: {error}")
        return
    body = "\n".join(failures)
    notify_send = shutil.which("notify-send") or "notify-send"
    for uid in sorted(uids):
        user = pwd.getpwuid(uid).pw_name
        bus = {"DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{uid}/bus"}
        send = ["runuser", "-u", user, "--", notify_send, "-u", "critical"]
        try:
            subprocess.run(
                [*send, "-a", "workloads", "Guests after host sleep", body],
                check=True,
                env=os.environ | bus,
                timeout=10,
            )
        except (OSError, subprocess.SubprocessError) as error:
            warn(f"no notification sent to {user}: {error}")


def bring_back(
    conn: libvirt.virConnect, paused: list[str], saved: list[str], failures: list[str]
) -> list[libvirt.virDomain]:
    """Restore, then resume, the recorded guests; return the ones brought back."""
    try:
        # Restore first: a guest paused for suspend and then saved comes back paused.
        woken = restore(recorded(conn, saved), failures)
        woken += resume(recorded(conn, paused), failures)
    except libvirt.libvirtError as error:
        fail(failures, f"guests may stay paused or saved: {error}")
        return []
    return list({domain.UUIDString(): domain for domain in woken}.values())


def bring_back_sessions(sessions: Sessions, users: list[str], failures: list[str]) -> None:
    """Restore, then resume, each recorded user's sandboxes."""
    for user in users:
        # Restore first, as for system guests.
        for phase in ("restore", "resume"):
            if (why := sessions.run(user, phase)) is not None:
                fail(failures, f"sandboxes of {user} may stay paused or saved: {why}")


def wake(connect: str, systemctl: str, sleep_units: list[str], sessions: Sessions | None) -> int:
    """Bring back the recorded guests and report failures; 1 if a guest stays down."""
    jobs = [systemctl, "list-jobs", "--no-legend", *sleep_units]
    down = False
    # A sleep cycle that ends while this runs merges its start into this job.
    while True:
        conn = None
        woken: list[libvirt.virDomain] = []
        with claimed_batch(jobs) as batch:
            if batch is None:
                return 1 if down else 0
            paused, saved, failures, users = batch
            earlier = len(failures)
            if paused or saved:
                try:
                    conn = libvirt.open(connect)
                except libvirt.libvirtError as error:
                    fail(failures, f"guests may stay paused or saved: {error}")
                else:
                    woken = bring_back(conn, paused, saved, failures)
            if sessions is not None:
                bring_back_sessions(sessions, users, failures)
        down = down or len(failures) > earlier
        if conn is not None:
            try:
                sync_clocks(woken)
            finally:
                conn.close()
        if failures:
            notify(failures)


def abort(failures: list[str], message: str) -> None:
    """Log the failure that aborts hibernation and keep it for the wake notification."""
    print(f"<3>error: {message}", file=sys.stderr, flush=True)
    failures.append(message)


def pre_system(phase: str, connect: str, failures: list[str]) -> None:
    """Pause or save the system guests."""
    try:
        # Appended, so records a wake never claimed are still brought back.
        with (PAUSED if phase == "pause" else SAVED).open("a") as records:
            conn = libvirt.open(connect)
            try:
                (pause if phase == "pause" else save)(conn, records, failures)
            finally:
                conn.close()
    except (SaveError, libvirt.libvirtError, OSError) as error:
        if phase == "pause":
            fail(failures, f"guests kept running through suspend: {error}")
        elif isinstance(error, SaveError):
            abort(failures, str(error))
        else:
            abort(failures, f"guests not saved, so the host did not sleep: {error}")


def pre_sessions(phase: str, sessions: Sessions, failures: list[str]) -> None:
    """Pause or save each user's sandboxes; a failed save stops at that user."""
    try:
        users = sessions.users()
        # Recorded first, so wake still runs for a user whose phase failed halfway.
        append(SESSIONS, users)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        if phase == "pause":
            fail(failures, f"sandboxes kept running through suspend: {error}")
        else:
            abort(failures, f"sandboxes not saved, so the host did not sleep: {error}")
        return
    for user in users:
        why = sessions.run(user, phase)
        if why is None:
            continue
        if phase == "pause":
            fail(failures, f"sandboxes of {user} may keep running through suspend: {why}")
        else:
            abort(failures, f"sandboxes of {user} not saved, so the host did not sleep: {why}")
            return


def pre(phase: str, connect: str, systemctl: str, sessions: Sessions | None) -> int:
    """Pause or save the guests before the host sleeps."""
    # No system guest runs without libvirtd; connecting would socket-activate it.
    active = [systemctl, "is-active", "--quiet", "libvirtd.service"]
    system = subprocess.run(active, check=False).returncode == 0
    if not system and sessions is None:
        return 0

    failures: list[str] = []
    try:
        with locked():
            if system:
                pre_system(phase, connect, failures)
            # A failed system save already aborts the transition.
            if sessions is not None and not (phase == "save" and failures):
                pre_sessions(phase, sessions, failures)
            if failures:
                try:
                    append(FAILURES, failures)
                except OSError as error:
                    warn(f"the wake notification will miss failures: {error}")
    except OSError as error:
        # Without the lock nothing was paused or saved.
        if phase == "pause":
            warn(f"guests kept running through suspend: {error}")
            return 0
        print(f"<3>error: guests not saved, so the host did not sleep: {error}", file=sys.stderr)
        return 1
    return 1 if phase == "save" and failures else 0


def main() -> int:
    """Run one sleep phase."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["pause", "save", "wake"])
    parser.add_argument("--connect", default="qemu:///system")
    parser.add_argument("--systemctl", default="systemctl")
    parser.add_argument("--sleep-unit", action="append", default=[], dest="sleep_units")
    parser.add_argument("--sbx", help="sbx to run as each user")
    parser.add_argument("--runuser", default="runuser")
    args = parser.parse_args()
    sessions = None if args.sbx is None else Sessions(args.sbx, args.runuser)

    # Expected lookup misses would otherwise print to stderr.
    libvirt.registerErrorHandler(lambda _ctx, _error: None, None)
    try:
        if args.phase == "wake":
            return wake(args.connect, args.systemctl, args.sleep_units, sessions)
    except (OSError, subprocess.CalledProcessError) as error:
        # Claimed records stay for the next wake.
        print(f"<3>error: wake: {error}", file=sys.stderr, flush=True)
        return 1

    return pre(args.phase, args.connect, args.systemctl, sessions)


if __name__ == "__main__":
    sys.exit(main())
