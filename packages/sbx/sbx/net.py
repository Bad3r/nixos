# Copyright (c) 2026 Bad3r
"""Egress NICs, DHCP leases, and workload grants of sandboxes."""

import copy
import json
import secrets
import socket
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import cast

from sbx.errors import SbxError
from sbx.model import DOMAIN_PREFIX

# workload-grantd's socket; modules/workloads/sharing/grants.nix declares it.
GRANT_SOCKET = Path("/run/workloads/grant.sock")


def random_mac() -> str:
    """Return a random address in QEMU's locally administered prefix."""
    return "52:54:00:" + ":".join(f"{byte:02x}" for byte in secrets.token_bytes(3))


def _lease_error(path: Path, detail: str) -> SbxError:
    msg = f"{path} is not a libvirt lease file: {detail}"
    return SbxError(msg, code="lease-file")


def revoke_grants(name: str, address: str | None) -> None:
    """End the workload grants of a removed sandbox; without the helper there are none."""
    request: dict[str, object] = {"verb": "revoke", "source": DOMAIN_PREFIX + name}
    if address is not None:
        request["address"] = address
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(30)
            connection.connect(str(GRANT_SOCKET))
            connection.sendall(json.dumps(request).encode())
            connection.shutdown(socket.SHUT_WR)
            answer = b"".join(iter(lambda: connection.recv(65536), b""))
    except FileNotFoundError:
        return
    except OSError as error:
        msg = f"workload-grantd is unreachable: {error}"
        raise SbxError(msg, code="grants") from error
    try:
        parsed: object = json.loads(answer)
    except json.JSONDecodeError as error:
        msg = f"workload-grantd answered no JSON: {error}"
        raise SbxError(msg, code="grants") from error
    if not isinstance(parsed, dict) or "revoked" not in parsed:
        msg = f"workload-grantd refused the revoke: {answer.decode(errors='replace').strip()}"
        raise SbxError(msg, code="grants")


def lease_address(path: Path, mac: str, now: float) -> str | None:
    """Return the IPv4 address the bridge's DHCP server leased to `mac`, if any."""
    mac = mac.lower()
    try:
        text = path.read_text()
    except FileNotFoundError:
        return None
    if not text.strip():
        return None
    try:
        leases = json.loads(text)
    except json.JSONDecodeError as error:
        raise _lease_error(path, str(error)) from error
    if not isinstance(leases, list):
        raise _lease_error(path, "not a list")
    best: tuple[float, str] | None = None
    for lease in cast("list[object]", leases):
        if not isinstance(lease, dict):
            raise _lease_error(path, "an entry is not an object")
        entry = cast("dict[str, object]", lease)
        address, owner, expiry = (
            entry.get("ip-address"),
            entry.get("mac-address"),
            entry.get("expiry-time"),
        )
        if not (isinstance(address, str) and isinstance(owner, str) and isinstance(expiry, int)):
            raise _lease_error(path, "an entry lacks ip-address, mac-address, or expiry-time")
        # libvirt's own reading: an expiry of 0 or below never expires.
        if owner.lower() != mac or ":" in address or 0 < expiry < now:
            continue
        rank = float("inf") if expiry <= 0 else float(expiry)
        if best is None or rank > best[0]:
            best = (rank, address)
    return None if best is None else best[1]


def bridge_interface(bridge: str, mac: str) -> ET.Element:
    """Render a virtio NIC on a host bridge; session libvirt joins it through qemu-bridge-helper."""
    interface = ET.Element("interface", type="bridge")
    ET.SubElement(interface, "mac", address=mac)
    ET.SubElement(interface, "source", bridge=bridge)
    ET.SubElement(interface, "model", type="virtio")
    # No <mtu>: session libvirt cannot set a tap's MTU, so guests take it from DHCP or the seed.
    return interface


def egress_interface(xml: str, mac: str | None) -> ET.Element | None:
    """Return the bridge NIC with `mac` in a domain definition, if it has one."""
    if mac is None:
        return None
    for interface in ET.fromstring(xml).iterfind("devices/interface[@type='bridge']"):  # noqa: S314
        address = interface.find("mac")
        if address is not None and str(address.get("address")).lower() == mac.lower():
            return interface
    return None


def link_down(interface: ET.Element) -> str:
    """Render a live NIC with its link down, for an in-place update."""
    changed = copy.deepcopy(interface)
    for link in changed.findall("link"):
        changed.remove(link)
    ET.SubElement(changed, "link", state="down")
    return ET.tostring(changed, encoding="unicode")


def unplug_xml(interface: ET.Element) -> str:
    """Render the MAC and bridge that name a NIC in both the live and the persistent definition."""
    mac, source = interface.find("mac"), interface.find("source")
    if mac is None or source is None:
        msg = "the egress interface has no MAC or bridge"
        raise SbxError(msg, code="internal")
    element = ET.Element("interface", type="bridge")
    ET.SubElement(element, "mac", address=str(mac.get("address")))
    ET.SubElement(element, "source", bridge=str(source.get("bridge")))
    return ET.tostring(element, encoding="unicode")
