# Copyright (c) 2026 Bad3r
"""Grant policy: targets, sources, and the netfilter paths a grant opens."""

import fnmatch
import ipaddress
import json
import re
import time
from dataclasses import dataclass
from pathlib import Path as FilePath
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

type Record = dict[str, object]

TARGET_PATTERN = re.compile(r"(host|guest|service):([a-z0-9][a-z0-9-]*)(?::([0-9]{1,5})(/udp)?)?")
SANDBOX_PATTERN = re.compile(r"sbx-[a-z0-9][a-z0-9-]{0,30}")
GUEST_PATTERN = re.compile(r"guest:([a-z0-9][a-z0-9-]*)")
DURATION_PATTERN = re.compile(r"([1-9][0-9]*)([smhd]?)")
DURATION_UNITS = {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}
MAC_PATTERN = re.compile(r"[0-9a-f]{2}(:[0-9a-f]{2}){5}")
PROTOCOLS = ("tcp", "udp")
MAX_PORT = 65535


class GrantError(Exception):
    """A refusal or failure reported with a code."""

    def __init__(self, message: str, *, code: str) -> None:
        """Keep the code next to the message."""
        super().__init__(message)
        self.code = code


def parse_duration(text: str) -> int:
    """Return seconds for `90`, `90s`, `30m`, `2h`, or `1d`."""
    match = DURATION_PATTERN.fullmatch(text)
    if match is None:
        msg = f"'{text}' is not a duration such as 30m, 2h, or 1d"
        raise GrantError(msg, code="invalid-argument")
    return int(match.group(1)) * DURATION_UNITS[match.group(2)]


def format_duration(seconds: int) -> str:
    """Render seconds as `1d`, or hours, minutes, and seconds such as `1h30m`."""
    if seconds and seconds % 86400 == 0:
        return f"{seconds // 86400}d"
    hours, rest = divmod(seconds, 3600)
    minutes, rest = divmod(rest, 60)
    parts = [
        f"{value}{unit}" for value, unit in ((hours, "h"), (minutes, "m"), (rest, "s")) if value
    ]
    return "".join(parts) or "0s"


@dataclass(frozen=True, order=True)
class Ports:
    """A protocol and an inclusive port range."""

    proto: str
    first: int
    last: int

    def covers(self, other: Ports) -> bool:
        """Whether every port of `other` lies inside this range."""
        return self.proto == other.proto and self.first <= other.first and other.last <= self.last

    def overlaps(self, other: Ports) -> bool:
        """Whether the two ranges share a port of the same protocol."""
        return self.proto == other.proto and self.first <= other.last and other.first <= self.last

    @property
    def text(self) -> str:
        """`8080` or `8000-8999`."""
        return str(self.first) if self.first == self.last else f"{self.first}-{self.last}"


@dataclass(frozen=True)
class Target:
    """`<kind>:<name>` with an optional single port."""

    kind: str
    name: str
    port: Ports | None

    @classmethod
    def parse(cls, text: str) -> Target:
        """Parse `host:<service>`, `guest:<name>`, or `service:<name>`, with `:<port>[/udp]`."""
        if text.startswith("sbx-"):
            msg = f"{text}: sandboxes are grant sources, not targets"
            raise GrantError(msg, code="invalid-target")
        match = TARGET_PATTERN.fullmatch(text)
        if match is None:
            msg = (
                f"'{text}' is no target: expected host:<service>, guest:<name>, or"
                " service:<name>, with an optional :<port>[/udp]"
            )
            raise GrantError(msg, code="invalid-target")
        kind, name, port_text, udp = match.groups()
        if port_text is None:
            return cls(kind, name, None)
        port = int(port_text)
        if not 1 <= port <= MAX_PORT:
            msg = f"{text}: ports lie between 1 and {MAX_PORT}"
            raise GrantError(msg, code="invalid-target")
        return cls(kind, name, Ports("udp" if udp else "tcp", port, port))

    def __str__(self) -> str:
        """The canonical text form."""
        base = f"{self.kind}:{self.name}"
        if self.port is None:
            return base
        return f"{base}:{self.port.first}" + ("/udp" if self.port.proto == "udp" else "")

    def covers(self, other: Target) -> bool:
        """Whether an allow entry naming this target admits `other`."""
        return (self.kind, self.name) == (other.kind, other.name) and (
            self.port is None or self.port == other.port
        )


@dataclass(frozen=True)
class Network:
    """A workload network as the policy file describes it."""

    name: str
    bridge: str
    subnet: ipaddress.IPv4Network
    gateway: ipaddress.IPv4Address
    isolate_peers: bool
    sandboxes: bool
    # The DHCP lease file of a sandbox network.
    leases: str | None


@dataclass(frozen=True)
class Interface:
    """An object's address on one network, and the MAC it sends from when it is a source."""

    network: Network
    address: ipaddress.IPv4Address
    mac: str | None = None


@dataclass(frozen=True)
class Endpoint:
    """A grant target: its addresses (none for host services) and grantable ports."""

    interfaces: tuple[Interface, ...]
    ports: tuple[Ports, ...]


@dataclass(frozen=True, order=True)
class Path:
    """One set element: ingress bridge, source MAC and address, destination, and ports."""

    bridge: str
    mac: str
    source: ipaddress.IPv4Address
    destination: ipaddress.IPv4Address
    ports: Ports

    @property
    def place(self) -> tuple[str, ipaddress.IPv4Address]:
        """Ingress bridge and source address: the identity of a source."""
        return self.bridge, self.source

    def conflicts(self, other: Path) -> bool:
        """Whether both would match the same connection, whichever MAC opened it."""
        return (self.bridge, self.source, self.destination) == (
            other.bridge,
            other.source,
            other.destination,
        ) and self.ports.overlaps(other.ports)

    def record(self) -> Record:
        """The JSON form."""
        return {
            "bridge": self.bridge,
            "mac": self.mac,
            "source": str(self.source),
            "destination": str(self.destination),
            "proto": self.ports.proto,
            "ports": self.ports.text,
        }


@dataclass(frozen=True, order=True)
class Route:
    """A policy-routing rule sending `source` to `destination` through the main table."""

    bridge: str
    source: ipaddress.IPv4Address
    destination: ipaddress.IPv4Address


@dataclass(frozen=True)
class Rule:
    """One `workloads.grants.allow` entry."""

    sources: tuple[str, ...]
    targets: tuple[Target, ...]
    max_ttl: int

    def admits(self, source: str, target: Target) -> bool:
        """Whether the rule names both the source and the target."""
        return any(fnmatch.fnmatchcase(source, pattern) for pattern in self.sources) and any(
            entry.covers(target) for entry in self.targets
        )


def leased_mac(text: str, address: str, now: float) -> str | None:
    """The MAC a libvirt lease file binds to the address, while the lease lives."""
    if not text.strip():
        return None
    for lease in cast("list[Record]", json.loads(text)):
        expiry = int(cast("int", lease["expiry-time"]))
        # libvirt's own reading: an expiry of 0 or below never expires.
        if lease["ip-address"] == address and (expiry <= 0 or expiry > now):
            mac = str(lease["mac-address"]).lower()
            if MAC_PATTERN.fullmatch(mac) is None:
                msg = f"the lease of {address} names no MAC: {mac!r}"
                raise GrantError(msg, code="lease-file")
            return mac
    return None


def _read_text(path: str) -> str:
    try:
        return FilePath(path).read_text()
    except FileNotFoundError:
        return ""


def _ports(value: object) -> tuple[Ports, ...]:
    return tuple(
        Ports(str(port["proto"]), int(cast("int", port["from"])), int(cast("int", port["to"])))
        for port in cast("list[Record]", value)
    )


@dataclass(frozen=True)
class Policy:
    """`/etc/workloads/grants.json`, which `modules/workloads/sharing/grants.nix` writes."""

    max_concurrent: int
    route_preference: int
    rules: tuple[Rule, ...]
    networks: dict[str, Network]
    sources: dict[str, tuple[Interface, ...]]
    targets: dict[str, dict[str, Endpoint]]
    reserved: frozenset[ipaddress.IPv4Address]

    @classmethod
    def from_json(cls, data: object) -> Policy:
        """Build the policy from its parsed JSON."""
        try:
            record = cast("Record", data)
            networks = {
                name: Network(
                    name,
                    str(network["bridge"]),
                    ipaddress.IPv4Network(str(network["subnet"])),
                    ipaddress.IPv4Address(str(network["gateway"])),
                    bool(network["isolatePeers"]),
                    bool(network["sandboxes"]),
                    None if network.get("leases") is None else str(network["leases"]),
                )
                for name, network in cast("dict[str, Record]", record["networks"]).items()
            }

            def interfaces(value: object) -> tuple[Interface, ...]:
                return tuple(
                    Interface(
                        networks[str(interface["network"])],
                        ipaddress.IPv4Address(str(interface["address"])),
                        None if interface.get("mac") is None else str(interface["mac"]).lower(),
                    )
                    for interface in cast("list[Record]", value)
                )

            targets = {
                kind: {
                    name: Endpoint(interfaces(entry.get("interfaces", [])), _ports(entry["ports"]))
                    for name, entry in cast("dict[str, Record]", entries).items()
                }
                for kind, entries in cast("dict[str, object]", record["targets"]).items()
            }
            rules = tuple(
                Rule(
                    tuple(str(source) for source in cast("list[object]", rule["from"])),
                    tuple(Target.parse(str(target)) for target in cast("list[object]", rule["to"])),
                    int(cast("int", rule["maxTtl"])),
                )
                for rule in cast("list[Record]", record["rules"])
            )
            return cls(
                max_concurrent=int(cast("int", record["maxConcurrent"])),
                route_preference=int(cast("int", record["routePreference"])),
                rules=rules,
                networks=networks,
                sources={
                    f"guest:{name}": interfaces(value)
                    for name, value in cast("dict[str, object]", record["sources"]).items()
                },
                targets=targets,
                reserved=frozenset(
                    ipaddress.IPv4Address(str(address))
                    for address in cast("list[object]", record["reserved"])
                ),
            )
        except (AttributeError, KeyError, TypeError, ValueError, GrantError) as error:
            msg = f"the grant policy is malformed: {error!r}"
            raise GrantError(msg, code="policy-file") from error

    def network_of(self, address: ipaddress.IPv4Address) -> Network | None:
        """The network whose subnet holds the address."""
        return next(
            (network for network in self.networks.values() if address in network.subnet), None
        )

    def identify(self, source: str, address: str | None) -> tuple[Interface, ...]:
        """The source's interfaces as named; a sandbox brings its own address."""
        if SANDBOX_PATTERN.fullmatch(source):
            if address is None:
                msg = f"{source} has no address on a workload network"
                raise GrantError(msg, code="no-address")
            try:
                parsed = ipaddress.IPv4Address(address)
            except ValueError as error:
                msg = f"'{address}' is no IPv4 address"
                raise GrantError(msg, code="invalid-request") from error
            network = self.network_of(parsed)
            if (
                network is None
                or not network.sandboxes
                or parsed in {network.gateway, network.subnet.network_address}
                or parsed == network.subnet.broadcast_address
                or parsed in self.reserved
            ):
                msg = f"{address} is no sandbox address on a network sandboxes attach to"
                raise GrantError(msg, code="invalid-source")
            return (Interface(network, parsed),)
        if GUEST_PATTERN.fullmatch(source) is None:
            msg = f"'{source}' is no source: expected sbx-<name> or guest:<name>"
            raise GrantError(msg, code="invalid-source")
        if address is not None:
            msg = f"{source}: only sandboxes bring an address"
            raise GrantError(msg, code="invalid-request")
        interfaces = self.sources.get(source)
        if not interfaces:
            msg = f"{source} is named by no grant rule"
            raise GrantError(msg, code="not-allowed")
        return interfaces

    def resolve_source(
        self,
        source: str,
        address: str | None,
        read_text: Callable[[str], str] = _read_text,
        now: Callable[[], float] = time.time,
    ) -> tuple[Interface, ...]:
        """The source's interfaces with the MAC each sends from; a sandbox needs a live lease."""
        interfaces = self.identify(source, address)
        if not SANDBOX_PATTERN.fullmatch(source):
            return interfaces
        (interface,) = interfaces
        network = interface.network
        if network.leases is None:
            msg = f"{network.name} names no lease file"
            raise GrantError(msg, code="policy-file")
        try:
            mac = leased_mac(read_text(network.leases), str(interface.address), now())
        except (KeyError, TypeError, ValueError, AttributeError) as error:
            msg = f"{network.leases} is no libvirt lease file: {error!r}"
            raise GrantError(msg, code="lease-file") from error
        if mac is None:
            msg = f"no live DHCP lease on {network.bridge} holds {interface.address}"
            raise GrantError(msg, code="no-lease")
        return (Interface(network, interface.address, mac),)

    def max_ttl(self, source: str, target: Target) -> int:
        """The longest TTL any rule naming both allows."""
        allowed = [rule.max_ttl for rule in self.rules if rule.admits(source, target)]
        if not allowed:
            msg = f"no workloads.grants.allow rule admits {source} to {target}"
            raise GrantError(msg, code="not-allowed")
        return max(allowed)

    def _endpoint(self, target: Target) -> tuple[Endpoint, tuple[Ports, ...]]:
        endpoint = self.targets.get(target.kind, {}).get(target.name)
        if endpoint is None:
            msg = f"{target.kind}:{target.name} is no grantable target"
            raise GrantError(msg, code="not-grantable")
        if target.port is None:
            return endpoint, endpoint.ports
        port = target.port
        if not any(spec.covers(port) for spec in endpoint.ports):
            msg = f"{target}: {port.text}/{port.proto} is not among the target's grantable ports"
            raise GrantError(msg, code="not-grantable")
        return endpoint, (port,)

    def ports(self, target: Target) -> tuple[Ports, ...]:
        """The grantable ports a grant to the target opens."""
        return self._endpoint(target)[1]

    def paths(self, interfaces: tuple[Interface, ...], target: Target) -> list[Path]:
        """The set elements a grant from these interfaces to the target needs."""
        endpoint, ports = self._endpoint(target)
        paths: list[Path] = []
        for interface in interfaces:
            network = interface.network
            if target.kind == "host":
                destination = network.gateway
            else:
                same = [peer for peer in endpoint.interfaces if peer.network == network]
                if same and network.isolate_peers:
                    msg = (
                        f"{target}: both sit on {network.name}, whose isolatePeers drops"
                        " traffic between its peers"
                    )
                    raise GrantError(msg, code="not-grantable")
                if same:
                    # Same-bridge peers already reach each other.
                    continue
                destination = endpoint.interfaces[0].address
            if interface.mac is None:
                msg = f"the policy names no MAC for the source on {network.name}"
                raise GrantError(msg, code="policy-file")
            paths.extend(
                Path(network.bridge, interface.mac, interface.address, destination, spec)
                for spec in ports
            )
        if not paths:
            msg = f"{target} is already reachable on the source's network"
            raise GrantError(msg, code="already-reachable")
        return paths

    def routes(self, path: Path) -> list[Route]:
        """Rules a path between two networks needs, one per direction."""
        source = self.network_of(path.source)
        destination = self.network_of(path.destination)
        if source is None or destination is None or source == destination:
            return []
        return [
            Route(source.bridge, path.source, path.destination),
            Route(destination.bridge, path.destination, path.source),
        ]
