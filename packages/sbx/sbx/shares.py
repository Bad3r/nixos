# Copyright (c) 2026 Bad3r
"""Runtime virtiofs shares of sandboxes.

A sandbox takes its own shared directory read-write, or a directory the host
declares in `workloads.grants.sandboxShares` read-only, and nothing else.
Session hot-plug needs no root, so sbx reads the grant helper's policy file
itself instead of asking the helper.
"""

import json
import os
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Protocol, cast

from sbx import journal
from sbx.core import DOMAIN_PREFIX, SHARED, Sandboxes, SbxError

if TYPE_CHECKING:
    from collections.abc import Callable

# Written by modules/workloads/sharing/grants.nix.
POLICY = Path("/etc/workloads/grants.json")
# libvirt itself waits five seconds for the guest to release a device.
DETACH_WAIT = 15.0
DETACH_POLL = 0.5


class ShareBackend(Protocol):
    """Live devices of session domains."""

    def live_xml(self, domain: str) -> str:
        """Return the live definition."""
        ...

    def attach_device(self, domain: str, xml: str) -> None:
        """Hot-plug a device into the running domain only."""
        ...

    def detach_device(self, domain: str, xml: str) -> None:
        """Ask the running domain to release a device."""
        ...


@dataclass(frozen=True)
class Device:
    """One live virtiofs device."""

    xml: str
    source: str
    read_only: bool


def declared(policy: Path) -> dict[str, Path]:
    """Return the read-only sandbox shares the policy file names; none without the file."""
    try:
        data: object = json.loads(policy.read_text())
    except FileNotFoundError:
        return {}
    except ValueError as error:
        msg = f"{policy} holds no valid JSON: {error}"
        raise SbxError(msg, code="policy-file") from error
    try:
        entries = cast(
            "dict[str, dict[str, object]]", cast("dict[str, object]", data)["sandboxShares"]
        )
        return {name: Path(str(entry["hostPath"])) for name, entry in entries.items()}
    except (AttributeError, KeyError, TypeError) as error:
        msg = f"{policy} holds no sandboxShares table: {error!r}"
        raise SbxError(msg, code="policy-file") from error


def attached(xml: str) -> dict[str, Device]:
    """Return the live virtiofs devices of a domain definition by tag."""
    devices: dict[str, Device] = {}
    for element in ET.fromstring(xml).iterfind("devices/filesystem"):  # noqa: S314
        driver, target = element.find("driver"), element.find("target")
        if driver is None or driver.get("type") != "virtiofs" or target is None:
            continue
        source = element.find("source")
        devices[str(target.get("dir"))] = Device(
            ET.tostring(element, encoding="unicode"),
            "" if source is None else str(source.get("dir")),
            element.find("readonly") is not None,
        )
    return devices


def device_xml(virtiofsd: str, source: Path, tag: str, *, read_only: bool) -> str:
    """Render the `<filesystem>` device of one share."""
    element = ET.Element("filesystem", type="mount", accessmode="passthrough")
    ET.SubElement(element, "driver", type="virtiofs")
    ET.SubElement(element, "binary", path=virtiofsd)
    ET.SubElement(element, "source", dir=str(source))
    ET.SubElement(element, "target", dir=tag)
    # Only the owner's ids in virtiofsd's namespace, so libvirt skips its /etc/subuid map;
    # the sbx-virtiofsd wrapper squashes every guest id onto them.
    idmap = ET.SubElement(element, "idmap")
    ET.SubElement(idmap, "uid", start="0", target=str(os.geteuid()), count="1")
    ET.SubElement(idmap, "gid", start="0", target=str(os.getegid()), count="1")
    if read_only:
        ET.SubElement(element, "readonly")
    return ET.tostring(element, encoding="unicode")


def _result(name: str, tag: str, source: str, *, read_only: bool, on: bool) -> dict[str, object]:
    return {
        "sandbox": name,
        "tag": tag,
        "read_only": read_only,
        "host_path": source,
        "attached": on,
    }


class Shares:
    """`sbx share attach` and `detach`."""

    def __init__(
        self,
        sandboxes: Sandboxes,
        policy: Path = POLICY,
        *,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        """Bind the sandboxes and the policy file."""
        self.sandboxes = sandboxes
        self.policy = policy
        self.sleep = sleep
        self.clock = clock

    def _backend(self) -> ShareBackend:
        return cast("ShareBackend", self.sandboxes.backend())

    def _source(self, name: str, tag: str) -> tuple[Path, bool]:
        """The resolved host directory of a share and whether it is read-only."""
        if tag == SHARED:
            try:
                shared = self.sandboxes.paths.sandbox(name).resolve(strict=True) / SHARED
                shared.mkdir(mode=0o700, exist_ok=True)
            except OSError as error:
                msg = f"the {SHARED} directory of {name} is unusable: {error}"
                raise SbxError(msg, code="path-denied") from error
            if shared.is_symlink() or not shared.is_dir():
                msg = f"{shared} is no directory"
                raise SbxError(msg, code="path-denied")
            return shared, False
        shares = declared(self.policy)
        if tag not in shares:
            msg = (
                f"'{tag}' is neither {SHARED} nor a workloads.grants.sandboxShares entry;"
                " a sandbox gets no other host directory"
            )
            raise SbxError(msg, code="not-declared")
        try:
            path = shares[tag].resolve(strict=True)
        except OSError as error:
            msg = f"sandbox share {tag}: {shares[tag]} is unreadable: {error.strerror}"
            raise SbxError(msg, code="path-denied") from error
        home, state = Path.home().resolve(), self.sandboxes.paths.root.resolve()
        if not path.is_dir():
            msg = f"sandbox share {tag}: {path} is no directory"
            raise SbxError(msg, code="path-denied")
        if home.is_relative_to(path) or state.is_relative_to(path) or path.is_relative_to(state):
            msg = f"sandbox share {tag}: {path} would expose $HOME or the sbx state directory"
            raise SbxError(msg, code="path-denied")
        return path, True

    def attach(self, name: str, tag: str) -> dict[str, object]:
        """Hot-plug a share into a running sandbox; it stays until detached or stopped."""
        with self.sandboxes.locked():
            sandbox = self.sandboxes.running(name)
            if self.sandboxes.windows_base(sandbox.meta.base) is not None:
                # As for system guests: virtiofs.exe needs a provisioning flow to mount.
                msg = f"sandbox '{name}' runs Windows, which takes no runtime share"
                raise SbxError(msg, code="unsupported-guest")
            domain = sandbox.domain.name
            source, read_only = self._source(name, tag)
            if not read_only:
                self.sandboxes.check_disk()
            backend = self._backend()
            if tag in attached(backend.live_xml(domain)):
                msg = f"sandbox '{name}' already holds {tag}"
                raise SbxError(msg, code="already-attached")
            journal.record(
                f"share {tag} attached to {name}",
                verb="share",
                sandbox=name,
                share=tag,
                read_only=read_only,
                session=self.sandboxes.session,
            )
            virtiofsd = self.sandboxes.settings.tools.virtiofsd
            backend.attach_device(domain, device_xml(virtiofsd, source, tag, read_only=read_only))
        return _result(name, tag, str(source), read_only=read_only, on=True)

    def detach(self, name: str, tag: str) -> dict[str, object]:
        """Remove a share and wait until the guest releases it; a held share is an error."""
        with self.sandboxes.locked():
            sandbox = self.sandboxes.find(name)
            if sandbox.domain.managed_save:
                msg = f"sandbox '{name}' is saved with its shares; restore it, then detach"
                raise SbxError(msg, code="saved")
            backend = self._backend()
            held = attached(backend.live_xml(sandbox.domain.name)) if sandbox.domain.active else {}
            if tag not in held:
                msg = f"sandbox '{name}' holds no {tag}"
                raise SbxError(msg, code="not-attached")
            device = held[tag]
            self._detach(name, tag, device)
        return _result(name, tag, device.source, read_only=device.read_only, on=False)

    def _detach(self, name: str, tag: str, device: Device, reason: str = "") -> None:
        """Detach under the caller's lock and wait until the device leaves."""
        domain = DOMAIN_PREFIX + name
        backend = self._backend()
        journal.record(
            f"share {tag} detached from {name}{reason}",
            verb="share",
            sandbox=name,
            share=tag,
            session=self.sandboxes.session,
        )
        backend.detach_device(domain, device.xml)
        deadline = self.clock() + DETACH_WAIT
        while tag in attached(backend.live_xml(domain)):
            if self.clock() >= deadline:
                msg = (
                    f"sandbox '{name}' still holds {tag} {DETACH_WAIT:g}s after the detach"
                    f" request; the share stays usable until the guest releases it, and"
                    f" `sbx destroy {name}` ends it"
                )
                raise SbxError(msg, code="detach-pending")
            self.sleep(DETACH_POLL)

    def reclaim(self, *, dry_run: bool) -> list[dict[str, str]]:
        """Detach every sandbox's shared directory while usage passes the cap or the floor."""
        if not self.sandboxes.has_state():
            return []
        actions: list[dict[str, str]] = []
        with self.sandboxes.locked():
            problem = self.sandboxes.disk_problem()
            if problem is None:
                return []
            for sandbox in self.sandboxes.owned():
                if not sandbox.domain.active:
                    continue
                device = attached(self._backend().live_xml(sandbox.domain.name)).get(SHARED)
                if device is None:
                    continue
                reason = f"{SHARED} detached: {problem}"
                if not dry_run:
                    try:
                        self._detach(sandbox.name, SHARED, device, f": {problem}")
                    except SbxError as error:
                        if error.code != "detach-pending":
                            raise
                        reason = f"{SHARED} still attached, {error.code}: {error}"
                actions.append({"name": sandbox.name, "reason": reason})
        return actions
