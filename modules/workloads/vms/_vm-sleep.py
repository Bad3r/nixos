# Copyright (c) 2026 Bad3r
"""Host sleep hook for guests on `qemu:///system`.

`pause` suspends running guests before host suspend, and `save` managed-saves active
guests before hibernation; each records the guests it acts on, and only `save` exits
non-zero, which aborts the sleep transition. `wake` runs after the sleep unit: it
resumes and restores the recorded guests, then resyncs their clocks. It tells each
active graphical session about every guest that failed a phase.
"""

import argparse
import os
import pwd
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import TextIO

import libvirt

STATE_DIR = Path("/run/workloads-vm-sleep")
PAUSED = STATE_DIR / "paused"
SAVED = STATE_DIR / "saved"
FAILURES = STATE_DIR / "failures"
# How long a guest agent may stay unconnected after resume, shared by all guests.
AGENT_WAIT = 15
AGENT_CHANNEL = "devices/channel/target[@name='org.qemu.guest_agent.0']"


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
        if domain.state()[0] != libvirt.VIR_DOMAIN_PAUSED:
            continue
        try:
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
        # Active means its save failed or someone started it.
        if domain.isActive():
            continue
        if not domain.hasManagedSaveImage():
            fail(failures, f"{domain.name()} has no managed save, so it stays shut off")
            continue
        try:
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
        # A guest saved while paused is restored paused.
        if domain.state()[0] != libvirt.VIR_DOMAIN_RUNNING or not has_agent(domain):
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


def read(path: Path) -> list[str]:
    """Return the lines a record holds."""
    try:
        return path.read_text().splitlines()
    except FileNotFoundError:
        return []


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


def wake(connect: str) -> int:
    """Bring back the recorded guests and report failures; 1 if a guest stays down."""
    paused, saved, failures = read(PAUSED), read(SAVED), read(FAILURES)
    earlier = len(failures)
    if paused or saved:
        try:
            conn = libvirt.open(connect)
            try:
                woken = resume(recorded(conn, paused), failures)
                woken += restore(recorded(conn, saved), failures)
                sync_clocks(woken)
            finally:
                conn.close()
        except libvirt.libvirtError as error:
            fail(failures, f"guests may stay paused or saved: {error}")
    if failures:
        notify(failures)
    for path in (PAUSED, SAVED, FAILURES):
        path.unlink(missing_ok=True)
    return 1 if len(failures) > earlier else 0


def main() -> int:
    """Run one sleep phase."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["pause", "save", "wake"])
    parser.add_argument("--connect", default="qemu:///system")
    parser.add_argument("--systemctl", default="systemctl")
    args = parser.parse_args()

    # Expected lookup misses would otherwise print to stderr.
    libvirt.registerErrorHandler(lambda _ctx, _error: None, None)
    try:
        if args.phase == "wake":
            return wake(args.connect)
    except OSError as error:
        print(f"<3>error: wake: {error}", file=sys.stderr, flush=True)
        return 1

    failures: list[str] = []
    try:
        STATE_DIR.mkdir(mode=0o700, exist_ok=True)
        with (PAUSED if args.phase == "pause" else SAVED).open("w") as records:
            # No system guest runs without libvirtd; connecting would socket-activate it.
            active = [args.systemctl, "is-active", "--quiet", "libvirtd.service"]
            if subprocess.run(active, check=False).returncode != 0:
                return 0
            conn = libvirt.open(args.connect)
            try:
                (pause if args.phase == "pause" else save)(conn, records, failures)
            finally:
                conn.close()
    except (SaveError, libvirt.libvirtError, OSError) as error:
        if args.phase == "pause":
            fail(failures, f"guests kept running through suspend: {error}")
        else:
            message = str(error)
            if not isinstance(error, SaveError):
                message = f"guests not saved, so the host did not sleep: {error}"
            print(f"<3>error: {message}", file=sys.stderr, flush=True)
            failures.append(message)
    finally:
        # Written even without failures, so wake never reports a stale list.
        try:
            FAILURES.write_text("".join(f"{failure}\n" for failure in failures))
        except OSError as error:
            warn(f"the wake notification will miss these failures: {error}")
    return 1 if args.phase == "save" and failures else 0


if __name__ == "__main__":
    sys.exit(main())
