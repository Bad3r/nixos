# Copyright (c) 2026 Bad3r
"""Runtime virtiofs shares of sandboxes.

A sandbox takes its own xfer directory read-write, or a directory the host
declares in `workloads.grants.sandboxShares` read-only, and nothing else.
Session hot-plug needs no root, so sbx reads the grant helper's policy file
itself instead of asking the helper.
"""

import json
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Protocol, cast

from sbx import journal
from sbx.core import Sandboxes, SbxError

if TYPE_CHECKING:
    from collections.abc import Callable

# Written by modules/workloads/sharing/grants.nix.
POLICY = Path("/etc/workloads/grants.json")
XFER = "xfer"
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
        """The host directory of a share and whether it is read-only."""
        if tag == XFER:
            xfer = self.sandboxes.paths.sandbox(name) / XFER
            if xfer.is_symlink() or not xfer.is_dir():
                msg = f"{xfer} is no directory"
                raise SbxError(msg, code="path-denied")
            return xfer, False
        shares = declared(self.policy)
        if tag not in shares:
            msg = (
                f"'{tag}' is neither {XFER} nor a workloads.grants.sandboxShares entry;"
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
        source, read_only = self._source(name, tag)
        with self.sandboxes.locked():
            domain = self.sandboxes.running(name).domain.name
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
            domain = sandbox.domain.name
            if sandbox.domain.managed_save:
                msg = f"sandbox '{name}' is saved with its shares; restore it, then detach"
                raise SbxError(msg, code="saved")
            backend = self._backend()
            held = attached(backend.live_xml(domain)) if sandbox.domain.active else {}
            if tag not in held:
                msg = f"sandbox '{name}' holds no {tag}"
                raise SbxError(msg, code="not-attached")
            device = held[tag]
            journal.record(
                f"share {tag} detached from {name}",
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
        return _result(name, tag, device.source, read_only=device.read_only, on=False)
