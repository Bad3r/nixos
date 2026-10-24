# Copyright (c) 2026 Bad3r
"""Host sleep hook for guests on `qemu:///system`.

`pause` suspends running guests before host suspend, and `resume` resumes them after.
`save` managed-saves active guests before hibernation, and `restore` starts them after.
A post phase acts only on the guests its pre phase recorded, then resyncs their clocks.
Only `save` exits non-zero, which aborts the sleep transition.
"""

import argparse
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import libvirt

STATE_DIR = Path("/run/workloads-vm-sleep")
RECORDS = {"pause": "paused", "resume": "paused", "save": "saved", "restore": "saved"}
# How long a guest agent may stay unconnected after resume, shared by all guests.
AGENT_WAIT = 15
AGENT_CHANNEL = "devices/channel/target[@name='org.qemu.guest_agent.0']"


def log(message: str) -> None:
    """Print one journal line."""
    print(message, flush=True)


def warn(message: str) -> None:
    """Print one journal line at warning priority."""
    print(f"<4>warning: {message}", flush=True)


def by_name(conn: libvirt.virConnect, flags: int) -> list[libvirt.virDomain]:
    """List domains matching `flags`, sorted by name."""
    return sorted(conn.listAllDomains(flags), key=lambda domain: domain.name())


def record(path: Path, domain: libvirt.virDomain) -> None:
    """Append a domain to a record before acting on it."""
    path.parent.mkdir(mode=0o700, exist_ok=True)
    with path.open("a") as records:
        records.write(f"{domain.UUIDString()}\n")


def recorded(conn: libvirt.virConnect, path: Path) -> list[libvirt.virDomain]:
    """Return the recorded domains that still exist."""
    try:
        uuids = dict.fromkeys(path.read_text().split())
    except FileNotFoundError:
        return []
    domains: list[libvirt.virDomain] = []
    for uuid in uuids:
        try:
            domains.append(conn.lookupByUUIDString(uuid))
        except libvirt.libvirtError as error:
            warn(f"recorded guest {uuid}: {error}")
    return domains


def pause(conn: libvirt.virConnect, path: Path) -> None:
    """Pause every running guest."""
    for domain in by_name(conn, libvirt.VIR_CONNECT_LIST_DOMAINS_RUNNING):
        record(path, domain)
        try:
            domain.suspend()
        except libvirt.libvirtError as error:
            warn(f"{domain.name()} keeps running through suspend: {error}")
        else:
            log(f"paused {domain.name()}")


def save(conn: libvirt.virConnect, path: Path) -> None:
    """Managed-save every active guest; the first failure raises."""
    for domain in by_name(conn, libvirt.VIR_CONNECT_LIST_DOMAINS_ACTIVE):
        record(path, domain)
        log(f"saving {domain.name()}")
        domain.managedSave()
        log(f"saved {domain.name()}")


def resume(conn: libvirt.virConnect, path: Path) -> list[libvirt.virDomain]:
    """Resume the recorded guests that are still paused."""
    resumed: list[libvirt.virDomain] = []
    for domain in recorded(conn, path):
        if domain.state()[0] != libvirt.VIR_DOMAIN_PAUSED:
            continue
        try:
            domain.resume()
        except libvirt.libvirtError as error:
            warn(f"{domain.name()} stays paused: {error}")
        else:
            log(f"resumed {domain.name()}")
            resumed.append(domain)
    return resumed


def restore(conn: libvirt.virConnect, path: Path) -> list[libvirt.virDomain]:
    """Start the recorded guests that are shut off with a managed save."""
    restored: list[libvirt.virDomain] = []
    for domain in recorded(conn, path):
        # Active means its save failed or someone started it.
        if domain.isActive():
            continue
        if not domain.hasManagedSaveImage():
            warn(f"{domain.name()} has no managed save, so it stays shut off")
            continue
        try:
            domain.create()
        except libvirt.libvirtError as error:
            warn(f"{domain.name()} stays saved: {error}")
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


def main() -> int:
    """Run one sleep phase."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=RECORDS)
    parser.add_argument("--connect", default="qemu:///system")
    args = parser.parse_args()
    path = STATE_DIR / RECORDS[args.phase]

    # Expected lookup misses would otherwise print to stderr.
    libvirt.registerErrorHandler(lambda _ctx, _error: None, None)
    try:
        conn = libvirt.open(args.connect)
        try:
            if args.phase == "pause":
                pause(conn, path)
            elif args.phase == "save":
                save(conn, path)
            else:
                post = resume if args.phase == "resume" else restore
                sync_clocks(post(conn, path))
                path.unlink(missing_ok=True)
        finally:
            conn.close()
    except (libvirt.libvirtError, OSError) as error:
        if args.phase == "save":
            print(f"<3>error: aborting the sleep transition: {error}", file=sys.stderr, flush=True)
            return 1
        warn(f"{args.phase}: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
