# Copyright (c) 2026 Bad3r
"""Load the bridge table that binds guests on workload bridges to their DHCP leases.

The table belongs to this script, not to the NixOS ruleset, so a ruleset
reload never empties the port pins. Each run adds what is missing, replaces
the rules and the leased pairs, and removes pins of ports that are gone and
objects of networks no longer declared, all in one transaction.
"""

import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

FAMILY = "bridge"
TABLE = "workload-leases"
TABLE_REF = f"{FAMILY} {TABLE}"
MAC = re.compile(r"[0-9a-f]{2}(:[0-9a-f]{2}){5}")
IPV4 = re.compile(r"[0-9]{1,3}(\.[0-9]{1,3}){3}")
# nft prints an ifindex no interface holds as bare digits.
GONE = re.compile(r"[0-9]+")
OBJECT = re.compile(r"(guest|pinned|ports|seen|macs|leases)-(.+)")


def nft(batch: str) -> None:
    """Apply one nft transaction."""
    subprocess.run(["nft", "-f", "-"], input=batch, text=True, check=True)


def current() -> list[dict[str, Any]]:
    """Return the table as nft JSON objects, or nothing when it does not exist."""
    result = subprocess.run(
        ["nft", "-j", "list", "table", FAMILY, TABLE], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        if "No such file or directory" in result.stderr:
            return []
        sys.exit(f"nft list table failed: {result.stderr.strip()}")
    return json.loads(result.stdout)["nftables"]


def leased(path: Path, now: int) -> list[str]:
    """Return set elements for the unexpired IPv4 leases in a libvirt status file."""
    try:
        text = path.read_text()
    except FileNotFoundError:
        return []
    elements: list[str] = []
    parsed: list[dict[str, Any]] = json.loads(text) if text.strip() else []
    for lease in parsed:
        mac: str = lease["mac-address"]
        address: str = lease["ip-address"]
        expiry: int = lease["expiry-time"]
        if not (MAC.fullmatch(mac) and IPV4.fullmatch(address)) or 0 < expiry <= now:
            continue
        timeout = f" timeout {expiry - now}s" if expiry > 0 else ""
        elements.append(f"{mac} . {address}{timeout}")
    return elements


def values(objects: list[dict[str, Any]], name: str) -> list[Any]:
    """Return the element values of one set."""
    for item in objects:
        if "set" in item and item["set"]["name"] == name:
            elements: list[Any] = item["set"].get("elem", [])
            # Elements with an expiry come wrapped.
            return [
                element["elem"]["val"] if "elem" in element else element for element in elements
            ]
    return []


def dynamic(key: str) -> str:
    """Return the spec of a set the packet path fills."""
    return f"{{ type {key}; flags dynamic, timeout; timeout 1h; }}"


def network_batch(network: dict[str, str], objects: list[dict[str, Any]], now: int) -> list[str]:
    """Return the commands for one network."""
    name, gateway, subnet = network["name"], network["gateway"], network["subnet"]
    guest, pinned = f"{TABLE_REF} guest-{name}", f"{TABLE_REF} pinned-{name}"
    ports, seen, macs, leases = (f"{kind}-{name}" for kind in ("ports", "seen", "macs", "leases"))
    pin = (
        f"update @{ports} {{ meta iif . ether saddr }} "
        f"update @{seen} {{ meta iif }} update @{macs} {{ ether saddr }}"
    )
    dhcp = (
        f"ip saddr {{ 0.0.0.0, {subnet} }} ip daddr {{ {gateway}, 255.255.255.255 }} "
        "udp sport 68 udp dport 67"
    )
    lines = [
        f"add set {TABLE_REF} {ports} {dynamic('iface_index . ether_addr')}",
        f"add set {TABLE_REF} {seen} {dynamic('iface_index')}",
        f"add set {TABLE_REF} {macs} {dynamic('ether_addr')}",
        f"add set {TABLE_REF} {leases} {{ type ether_addr . ipv4_addr; flags timeout; }}",
        f"add chain {guest}",
        f"add chain {pinned}",
        f"flush chain {guest}",
        f"flush chain {pinned}",
        # One MAC per port, and no MAC on two ports, ahead of every exemption.
        f"add rule {guest} meta iif . ether saddr @{ports} {pin} goto pinned-{name}",
        f"add rule {guest} meta iif @{seen} drop",
        f"add rule {guest} ether saddr @{macs} drop",
        f"add rule {guest} {pin} goto pinned-{name}",
        # A failed update must not fall through to the base chain's accept.
        f"add rule {guest} drop",
        f"add rule {pinned} ether type != {{ ip, arp }} drop",
        # A guest whose pair is missing can still renew and so restore it.
        f"add rule {pinned} {dhcp} accept",
        f"add rule {pinned} ether type ip ether saddr . ip saddr != @{leases} drop",
        f"add rule {pinned} ether type arp meta iif . arp saddr ether != @{ports} drop",
        # ARP probes announce no address yet.
        f"add rule {pinned} arp saddr ip 0.0.0.0 accept",
        f"add rule {pinned} ether type arp ether saddr . arp saddr ip != @{leases} drop",
        f"flush set {TABLE_REF} {leases}",
    ]
    if elements := leased(Path(network["status"]), now):
        lines.append(f"add element {TABLE_REF} {leases} {{ {', '.join(elements)} }}")
    # Pins of removed ports would hold their MAC for the full timeout.
    for value in values(objects, ports):
        port, mac = value["concat"]
        if GONE.fullmatch(str(port)):
            lines += [
                f"destroy element {TABLE_REF} {ports} {{ {port} . {mac} }}",
                f"destroy element {TABLE_REF} {seen} {{ {port} }}",
                f"destroy element {TABLE_REF} {macs} {{ {mac} }}",
            ]
    return lines


def stale_objects(objects: list[dict[str, Any]], declared: set[str]) -> dict[str, list[str]]:
    """Return the chains and sets of networks no longer declared."""
    stale: dict[str, list[str]] = {"chain": [], "set": []}
    for item in objects:
        for kind, stale_names in stale.items():
            if kind not in item:
                continue
            name: str = item[kind]["name"]
            match = OBJECT.fullmatch(name)
            if match and match.group(2) not in declared:
                stale_names.append(name)
    return stale


def main() -> None:
    """Load the table for the networks in the JSON file named on the command line."""
    networks: list[dict[str, str]] = json.loads(Path(sys.argv[1]).read_text())
    now = int(time.time())
    objects = current()
    stale = stale_objects(objects, {network["name"] for network in networks})
    base = "{ type filter hook prerouting priority filter; policy accept; }"
    lines = [
        f"add table {TABLE_REF}",
        f"add chain {TABLE_REF} prerouting {base}",
        f"flush chain {TABLE_REF} prerouting",
    ]
    lines += [f"flush chain {TABLE_REF} {chain}" for chain in stale["chain"]]
    lines += [f"delete chain {TABLE_REF} {chain}" for chain in stale["chain"]]
    lines += [f"delete set {TABLE_REF} {name}" for name in stale["set"]]
    for network in networks:
        lines += network_batch(network, objects, now)
        bridge, name = network["bridge"], network["name"]
        lines.append(f'add rule {TABLE_REF} prerouting meta ibrname "{bridge}" jump guest-{name}')
    nft("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
