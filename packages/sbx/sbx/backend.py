# Copyright (c) 2026 Bad3r
"""Local qemu:///session backend.

The session daemon runs as the user unit that places it in sbx.slice, so QEMU
and every helper it spawns inherit the slice's memory and CPU limits.
"""

import importlib
import json
import os
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, BinaryIO

from sbx.core import NS, DomainInfo, Meta, SbxError, Settings

# libvirt-python ships no type information the checker can read.
libvirt: Any = importlib.import_module("libvirt")
libvirt_qemu: Any = importlib.import_module("libvirt_qemu")

URI = "qemu:///session"
STATES = {
    0: "nostate",
    1: "running",
    2: "blocked",
    3: "paused",
    4: "shutdown",
    5: "shutoff",
    6: "crashed",
    7: "pmsuspended",
}


def _runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")


def _qemu_pid(domain: str) -> int | None:
    try:
        return int((_runtime_dir() / "libvirt" / "qemu" / "run" / f"{domain}.pid").read_text())
    except OSError, ValueError:
        return None


def _daemon_cgroup() -> tuple[int | None, str]:
    pidfile = _runtime_dir() / "libvirt" / "virtqemud.pid"
    try:
        pid = int(pidfile.read_text().strip())
        return pid, Path(f"/proc/{pid}/cgroup").read_text()
    except OSError, ValueError:
        return None, ""


def ensure_daemon(settings: Settings, *, require_slice: bool) -> None:
    """Start the session daemon unit; refuse a daemon outside the slice when asked."""
    started = subprocess.run(
        [settings.tools.systemctl, "--user", "start", settings.unit],
        capture_output=True,
        text=True,
        check=False,
    )
    pid, cgroup = _daemon_cgroup()
    if pid is None:
        msg = f"cannot start {settings.unit}: {started.stderr.strip()}"
        raise SbxError(msg, code="daemon")
    if require_slice and f"/{settings.slice}/{settings.unit}" not in cgroup:
        msg = (
            f"the qemu:///session daemon (pid {pid}) runs outside {settings.slice}; "
            "close the client that spawned it, such as virt-manager, stop that virtqemud, "
            "and retry"
        )
        raise SbxError(msg, code="daemon-outside-slice")


def _ignore_error(_context: object, _error: object) -> None:
    return


def _write(_stream: object, data: bytes, out: BinaryIO) -> int:
    return out.write(data)


def _error(error: Exception) -> SbxError:
    return SbxError(str(error), code="libvirt")


class LibvirtBackend:
    """Session domains through libvirt-python."""

    def __init__(self, settings: Settings, *, require_slice: bool, start: bool = True) -> None:
        """Connect without letting libvirt autospawn a daemon outside the slice.

        Without `start`, attach only to a daemon that already runs; a refused
        connection raises the `no-daemon` code.
        """
        if start:
            ensure_daemon(settings, require_slice=require_slice)
        os.environ["LIBVIRT_AUTOSTART"] = "0"
        # Expected lookup misses would otherwise print to stderr.
        libvirt.registerErrorHandler(_ignore_error, None)
        try:
            self._conn: Any = libvirt.open(URI)
        except libvirt.libvirtError as error:
            if not start:
                raise SbxError(str(error), code="no-daemon") from error
            raise _error(error) from error

    def _lookup(self, domain: str) -> Any:  # noqa: ANN401
        try:
            return self._conn.lookupByName(domain)
        except libvirt.libvirtError as error:
            raise _error(error) from error

    def domains(self) -> list[DomainInfo]:
        """List every session domain with its sbx metadata."""
        result: list[DomainInfo] = []
        try:
            for domain in self._conn.listAllDomains(0):
                root = ET.fromstring(domain.XMLDesc(0))  # noqa: S314
                element = root.find(f"metadata/{{{NS}}}sandbox")
                cid = root.find("devices/vsock/cid")
                address = None if cid is None else cid.get("address")
                mac = root.find("devices/interface[@type='bridge']/mac")
                state = domain.state()[0]
                result.append(
                    DomainInfo(
                        name=domain.name(),
                        state=STATES.get(state, "unknown"),
                        active=bool(domain.isActive()),
                        memory_mib=int(root.findtext("memory", "0")) // 1024,
                        cpus=int(root.findtext("vcpu", "0")),
                        cid=None if address is None else int(address),
                        meta=None if element is None else Meta.parse(element),
                        managed_save=bool(domain.hasManagedSaveImage(0)),
                        mac=None if mac is None else mac.get("address"),
                        pid=_qemu_pid(domain.name()) if domain.isActive() else None,
                        emulator=root.findtext("devices/emulator"),
                    )
                )
        except libvirt.libvirtError as error:
            raise _error(error) from error
        return result

    def start(self, xml: str) -> None:
        """Define a persistent domain and start it."""
        try:
            self._conn.defineXML(xml).create()
        except libvirt.libvirtError as error:
            raise _error(error) from error

    def remove(self, domain: str) -> None:
        """Stop a domain if it runs, then undefine it with NVRAM and saved state."""
        handle = self._lookup(domain)
        flags = (
            libvirt.VIR_DOMAIN_UNDEFINE_NVRAM
            | libvirt.VIR_DOMAIN_UNDEFINE_MANAGED_SAVE
            | libvirt.VIR_DOMAIN_UNDEFINE_SNAPSHOTS_METADATA
            | libvirt.VIR_DOMAIN_UNDEFINE_CHECKPOINTS_METADATA
        )
        try:
            if handle.isActive():
                handle.destroy()
            handle.undefineFlags(flags)
        except libvirt.libvirtError as error:
            raise _error(error) from error

    def agent(self, domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:
        """Run one qemu-ga command."""
        handle = self._lookup(domain)
        try:
            reply = libvirt_qemu.qemuAgentCommand(handle, json.dumps(command), timeout, 0)
        except libvirt.libvirtError as error:
            raise _error(error) from error
        return json.loads(reply)

    def screenshot(self, domain: str, target: Path) -> str:
        """Stream the primary display into a file."""
        handle = self._lookup(domain)
        stream = self._conn.newStream(0)
        try:
            mime = handle.screenshot(stream, 0, 0)
            with target.open("wb") as out:
                stream.recvAll(_write, out)
            stream.finish()
        except libvirt.libvirtError as error:
            stream.abort()
            target.unlink(missing_ok=True)
            raise _error(error) from error
        return str(mime)

    def _call(self, domain: str, method: str, *args: object) -> None:
        handle = self._lookup(domain)
        try:
            getattr(handle, method)(*args)
        except libvirt.libvirtError as error:
            raise _error(error) from error

    def suspend(self, domain: str) -> None:
        """Pause a running domain."""
        self._call(domain, "suspend")

    def resume(self, domain: str) -> None:
        """Continue a paused domain."""
        self._call(domain, "resume")

    def managed_save(self, domain: str) -> None:
        """Save an active domain's state and stop it."""
        self._call(domain, "managedSave", 0)

    def restore(self, domain: str) -> None:
        """Start a defined domain, from its managed save when it has one."""
        self._call(domain, "create")

    def job_active(self, domain: str) -> bool:
        """Return whether a job, such as a managed save, runs on a domain."""
        handle = self._lookup(domain)
        try:
            return handle.jobInfo()[0] != libvirt.VIR_DOMAIN_JOB_NONE
        except libvirt.libvirtError as error:
            raise _error(error) from error

    def abort_job(self, domain: str) -> None:
        """Abort a domain's running job; an aborted managed save leaves the guest running."""
        self._call(domain, "abortJob")

    def set_time(self, domain: str) -> None:
        """Set the guest clock to the host's through qemu-ga."""
        handle = self._lookup(domain)
        now = time.time_ns()
        try:
            handle.setTime({"seconds": now // 10**9, "nseconds": now % 10**9}, 0)
        except libvirt.libvirtError as error:
            unconnected = error.get_error_code() == libvirt.VIR_ERR_AGENT_UNRESPONSIVE
            raise SbxError(
                str(error), code="agent-unresponsive" if unconnected else "libvirt"
            ) from error
