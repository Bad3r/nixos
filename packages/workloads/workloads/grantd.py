# Copyright (c) 2026 Bad3r
"""workload-grantd: one grant or share request per connection, as root with CAP_NET_ADMIN only."""

import contextlib
import fcntl
import ipaddress
import json
import os
import re
import secrets
import socket
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path as FilePath
from typing import TYPE_CHECKING, Protocol, cast

from workloads.grants import (
    SANDBOX_PATTERN,
    GrantError,
    Path,
    Policy,
    Ports,
    Record,
    Route,
    RuntimeShare,
    ShareGuest,
    Target,
)

if TYPE_CHECKING:
    from collections.abc import Callable, Generator, Sequence
    from contextlib import AbstractContextManager

SET = ("inet", "workload_grants", "grants")
# Ingress bridge, MAC, and address of every source that holds a grant.
SOURCES = ("inet", "workload_grants", "sources")
COMMAND_TIMEOUT = 10
REQUEST_LIMIT = 16384
ID_PATTERN = re.compile(r"[0-9a-f]{8}")
# nft refuses longer element comments.
COMMENT_LIMIT = 128
JOURNAL_SOCKET = "/run/systemd/journal/socket"
KERNEL_CODES = frozenset({"nft", "route", "journal", "libvirt", "detach-pending"})
LIBVIRT_URI = "qemu:///system"
# libvirt itself waits five seconds for the guest to release a device.
DETACH_WAIT = 15.0
DETACH_POLL = 0.5

# Runs argv with optional stdin and returns the exit code, stdout, and stderr.
type Runner = Callable[[Sequence[str], str | None], tuple[int, str, str]]
type Log = Callable[[str, dict[str, object]], None]


@dataclass(frozen=True)
class Element:
    """One live set element and the grant its comment names."""

    path: Path
    grant: str
    source: str
    target: str
    expires: int

    @property
    def comment(self) -> str:
        """The element comment: id, source, target, and the source's MAC."""
        return f"{self.grant} {self.source} {self.target} {self.path.mac}"


class Kernel(Protocol):
    """The netfilter and routing state the helper reads and writes."""

    def elements(self) -> list[Element]:
        """Live grant elements."""
        ...

    def add(self, elements: Sequence[Element], ttl: int, source_ttl: int) -> None:
        """Add elements and their source, which must outlive every grant it holds."""
        ...

    def remove(self, elements: Sequence[Element], sources: Sequence[Path]) -> None:
        """Remove elements and the sources left without one; expired ones are no error."""
        ...

    def routes(self, preference: int) -> set[Route]:
        """Policy-routing rules at the grant preference."""
        ...

    def add_route(self, preference: int, route: Route) -> None:
        """Add one rule."""
        ...

    def delete_route(self, preference: int, route: Route) -> None:
        """Delete one rule."""
        ...


@dataclass(frozen=True)
class LiveShare:
    """A virtiofs device in a live definition."""

    alias: str
    read_only: bool


class Libvirt(Protocol):
    """The system guests' live devices."""

    def state(self, domain: str) -> str:
        """`running`, `paused`, `shut off`, and so on."""
        ...

    def saved(self, domain: str) -> bool:
        """Whether a managed save image holds the guest, live devices included."""
        ...

    def shares(self, domain: str) -> dict[str, LiveShare]:
        """The virtiofs shares in the live definition by tag."""
        ...

    def attach(self, domain: str, device: str) -> None:
        """Hot-plug the device in the file into the running guest."""
        ...

    def detach(self, domain: str, alias: str) -> None:
        """Ask the running guest to release a live device."""
        ...


@dataclass(frozen=True)
class Tools:
    """Absolute paths of the programs the helper runs."""

    nft: str
    ip: str
    virsh: str


def run_command(argv: Sequence[str], stdin: str | None) -> tuple[int, str, str]:
    """Run a tool and capture its output; a hung tool fails like any other."""
    try:
        result = subprocess.run(
            list(argv),
            input=stdin,
            capture_output=True,
            text=True,
            check=False,
            timeout=COMMAND_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {COMMAND_TIMEOUT}s"
    return result.returncode, result.stdout, result.stderr


def _key(path: Path) -> str:
    return (
        f'"{path.bridge}" . {path.source} . {path.destination} . {path.ports.proto}'
        f" . {path.ports.text}"
    )


def _source_key(path: Path) -> str:
    return f'"{path.bridge}" . {path.mac} . {path.source}'


def _parse_element(item: object) -> Element:
    entry = cast("Record", item)
    elem = cast("Record", entry["elem"]) if "elem" in entry else entry
    bridge, source, destination, proto, port = cast(
        "list[object]", cast("Record", elem["val"])["concat"]
    )
    if isinstance(port, dict):
        first, last = cast("list[int]", cast("Record", port)["range"])
    else:
        first = last = int(cast("int", port))
    comment = str(elem.get("comment", ""))
    parts = comment.split(" ")
    if len(parts) != 4 or ID_PATTERN.fullmatch(parts[0]) is None:  # noqa: PLR2004
        msg = (
            f"element {bridge} . {source} . {destination} . {proto} . {first}-{last} carries"
            f" no grant comment ('{comment}'); delete it with nft delete element"
        )
        raise GrantError(msg, code="nft")
    return Element(
        Path(
            str(bridge),
            parts[3],
            ipaddress.IPv4Address(str(source)),
            ipaddress.IPv4Address(str(destination)),
            Ports(str(proto), first, last),
        ),
        parts[0],
        parts[1],
        parts[2],
        int(cast("int", elem.get("expires", elem.get("timeout", 0)))),
    )


class NftKernel:
    """Kernel state through nft and ip."""

    def __init__(self, tools: Tools, run: Runner = run_command) -> None:
        """Keep the tool paths and the runner."""
        self.tools = tools
        self.run = run

    def _checked(self, code: str, argv: Sequence[str], stdin: str | None = None) -> str:
        status, stdout, stderr = self.run(argv, stdin)
        if status != 0:
            msg = f"{' '.join(argv[:3])} failed: {stderr.strip() or stdout.strip()}"
            raise GrantError(msg, code=code)
        return stdout

    def elements(self) -> list[Element]:
        """Parse `nft -j list set`."""
        output = self._checked("nft", [self.tools.nft, "-j", "list", "set", *SET])
        try:
            listing = cast("list[Record]", cast("Record", json.loads(output))["nftables"])
            nft_set = next(cast("Record", item["set"]) for item in listing if "set" in item)
            return [_parse_element(item) for item in cast("list[object]", nft_set.get("elem", []))]
        except (KeyError, StopIteration, TypeError, ValueError) as error:
            msg = f"nft printed a malformed grant set: {error!r}"
            raise GrantError(msg, code="nft") from error

    def _write(self, lines: Sequence[str]) -> None:
        """One nft transaction, so a grant and its source change together."""
        if lines:
            self._checked(
                "nft", [self.tools.nft, "-f", "-"], "".join(f"{line}\n" for line in lines)
            )

    def add(self, elements: Sequence[Element], ttl: int, source_ttl: int) -> None:
        """Add with the TTL as the element timeout, and set the source's expiry afresh.

        Re-adding an existing element need not move its expiry, so the source is
        destroyed and added again in the same transaction.
        """
        if not elements:
            return
        grants = ", ".join(f'{_key(e.path)} timeout {ttl}s comment "{e.comment}"' for e in elements)
        keys = sorted({_source_key(e.path) for e in elements})
        sources = ", ".join(f"{key} timeout {source_ttl}s" for key in keys)
        self._write(
            [
                f"add element {' '.join(SET)} {{ {grants} }}",
                f"destroy element {' '.join(SOURCES)} {{ {', '.join(keys)} }}",
                f"add element {' '.join(SOURCES)} {{ {sources} }}",
            ]
        )

    def remove(self, elements: Sequence[Element], sources: Sequence[Path]) -> None:
        """`destroy` tolerates elements that expired since the listing."""
        lines: list[str] = []
        if elements:
            keys = ", ".join(_key(element.path) for element in elements)
            lines.append(f"destroy element {' '.join(SET)} {{ {keys} }}")
        if sources:
            keys = ", ".join(sorted({_source_key(path) for path in sources}))
            lines.append(f"destroy element {' '.join(SOURCES)} {{ {keys} }}")
        self._write(lines)

    def routes(self, preference: int) -> set[Route]:
        """Parse `ip -j rule show pref`."""
        output = self._checked(
            "route", [self.tools.ip, "-j", "rule", "show", "pref", str(preference)]
        )
        try:
            rules = cast("list[Record]", json.loads(output or "[]"))
            routes: set[Route] = set()
            for rule in rules:
                if (
                    set(rule) != {"priority", "iif", "src", "dst", "table"}
                    or rule["table"] != "main"
                ):
                    msg = (
                        f"preference {preference} holds a rule no grant made: {rule};"
                        " move it, since the helper owns that preference"
                    )
                    raise GrantError(msg, code="route")
                routes.add(
                    Route(
                        str(rule["iif"]),
                        ipaddress.IPv4Address(str(rule["src"])),
                        ipaddress.IPv4Address(str(rule["dst"])),
                    )
                )
        except (KeyError, TypeError, ValueError) as error:
            msg = f"ip printed a malformed rule at preference {preference}: {error!r}"
            raise GrantError(msg, code="route") from error
        return routes

    def _rule(self, verb: str, preference: int, route: Route) -> None:
        self._checked(
            "route",
            [
                self.tools.ip,
                "rule",
                verb,
                "pref",
                str(preference),
                "iif",
                route.bridge,
                "from",
                str(route.source),
                "to",
                str(route.destination),
                "lookup",
                "main",
            ],
        )

    def add_route(self, preference: int, route: Route) -> None:
        """`ip rule add`."""
        self._rule("add", preference, route)

    def delete_route(self, preference: int, route: Route) -> None:
        """`ip rule del`."""
        self._rule("del", preference, route)


def virtiofs_shares(xml: str) -> dict[str, LiveShare]:
    """The virtiofs `<filesystem>` devices of a live domain definition by tag."""
    root = ET.fromstring(xml)  # noqa: S314
    shares: dict[str, LiveShare] = {}
    for device in root.iterfind("devices/filesystem"):
        driver, target, alias = device.find("driver"), device.find("target"), device.find("alias")
        if driver is None or driver.get("type") != "virtiofs" or target is None:
            continue
        shares[str(target.get("dir"))] = LiveShare(
            "" if alias is None else str(alias.get("name")), device.find("readonly") is not None
        )
    return shares


class Virsh:
    """System guests through virsh; libvirt admits a root client without polkit."""

    def __init__(self, virsh: str, run: Runner = run_command) -> None:
        """Keep the virsh path and the runner."""
        self.virsh = virsh
        self.run = run

    def _checked(self, *arguments: str) -> str:
        argv = [self.virsh, "-c", LIBVIRT_URI, *arguments]
        status, stdout, stderr = self.run(argv, None)
        if status != 0:
            msg = f"virsh {arguments[0]} failed: {stderr.strip() or stdout.strip()}"
            raise GrantError(msg, code="libvirt")
        return stdout

    def state(self, domain: str) -> str:
        """`virsh domstate`."""
        return self._checked("domstate", domain).strip()

    def saved(self, domain: str) -> bool:
        """Read `Managed save` from `virsh dominfo`."""
        for line in self._checked("dominfo", domain).splitlines():
            key, _, value = line.partition(":")
            if key.strip() == "Managed save":
                return value.strip() == "yes"
        msg = f"virsh dominfo {domain} printed no managed save line"
        raise GrantError(msg, code="libvirt")

    def shares(self, domain: str) -> dict[str, LiveShare]:
        """Parse `virsh dumpxml`."""
        output = self._checked("dumpxml", domain)
        try:
            return virtiofs_shares(output)
        except ET.ParseError as error:
            msg = f"virsh dumpxml {domain} printed no XML: {error}"
            raise GrantError(msg, code="libvirt") from error

    def attach(self, domain: str, device: str) -> None:
        """`virsh attach-device --live`."""
        self._checked("attach-device", domain, device, "--live")

    def detach(self, domain: str, alias: str) -> None:
        """`virsh detach-device-alias --live`, which returns once the request is sent."""
        self._checked("detach-device-alias", domain, alias, "--live")


@dataclass(frozen=True)
class Caller:
    """The peer of the socket connection."""

    pid: int
    uid: int
    cmdline: str


def _string(request: Record, key: str) -> str:
    value = request[key]
    if not isinstance(value, str):
        msg = f"'{key}' must be a string"
        raise GrantError(msg, code="invalid-request")
    return value


def _optional_string(request: Record, key: str) -> str | None:
    return _string(request, key) if request.get(key) is not None else None


def _check_keys(request: Record, required: set[str], optional: set[str]) -> None:
    keys = set(request)
    missing, unknown = required - keys, keys - required - optional
    if missing or unknown:
        msg = f"request keys: missing {sorted(missing)}, unknown {sorted(unknown)}"
        raise GrantError(msg, code="invalid-request")


def describe(elements: Sequence[Element]) -> list[Record]:
    """Group elements into grants."""
    grouped: dict[str, list[Element]] = {}
    for element in elements:
        grouped.setdefault(element.grant, []).append(element)
    return [
        {
            "id": grant,
            "source": members[0].source,
            "target": members[0].target,
            "expires_in": min(member.expires for member in members),
            "paths": [member.path.record() for member in sorted(members, key=lambda m: m.path)],
        }
        for grant, members in sorted(grouped.items(), key=lambda item: (item[1][0].source, item[0]))
    ]


class Service:
    """Validates one request against the policy and applies it."""

    def __init__(  # noqa: PLR0913
        self,
        load_policy: Callable[[], Policy],
        kernel: Kernel,
        log: Log,
        lock: Callable[[], AbstractContextManager[object]],
        *,
        libvirt: Libvirt,
        new_id: Callable[[], str] = lambda: secrets.token_hex(4),
        read_text: Callable[[str], str] | None = None,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        """Keep the collaborators; the policy loads per request."""
        self.load_policy = load_policy
        self.kernel = kernel
        self.log = log
        self.lock = lock
        self.libvirt = libvirt
        self.new_id = new_id
        self.read_text = read_text
        self.sleep = sleep
        self.clock = clock

    def handle(self, raw: bytes, caller: Caller) -> Record:
        """Answer one request; every decision reaches the journal before it applies."""
        context: dict[str, object] = {
            "caller_pid": caller.pid,
            "caller_uid": caller.uid,
            "caller_cmdline": caller.cmdline,
        }

        def record(decision: str, message: str, **fields: object) -> None:
            entry = context | {"decision": decision} | fields
            try:
                self.log(message, entry)
            except OSError as error:
                msg = f"cannot write to the journal: {error}"
                raise GrantError(msg, code="journal") from error

        try:
            request = self._parse(raw)
            context["session"] = _optional_string(request, "session")
            context |= {
                key: request[key]
                for key in ("verb", "source", "target", "id", "guest", "share")
                if key in request
            }
            policy = self.load_policy()
            match request["verb"]:
                case "grant":
                    return self._grant(policy, request, record)
                case "revoke":
                    return self._revoke(policy, request, record)
                case "share-attach" | "share-detach":
                    return self._share(policy, request, record)
                case _:
                    record("listed", "listed grants")
                    return {"grants": describe(self.kernel.elements())}
        except GrantError as error:
            decision = "failed" if error.code in KERNEL_CODES else "refused"
            with contextlib.suppress(GrantError):
                record(decision, f"{decision}: {error}", error=error.code)
            return {"error": {"code": error.code, "message": str(error)}}

    @staticmethod
    def _parse(raw: bytes) -> Record:
        try:
            parsed: object = json.loads(raw)
        except ValueError as error:
            msg = f"the request is no JSON: {error}"
            raise GrantError(msg, code="invalid-request") from error
        if not isinstance(parsed, dict):
            msg = "the request is no JSON object"
            raise GrantError(msg, code="invalid-request")
        request = cast("Record", parsed)
        verb = request.get("verb")
        if verb == "grant":
            _check_keys(request, {"verb", "source", "target", "ttl"}, {"address", "session"})
            ttl = request["ttl"]
            if not isinstance(ttl, int) or isinstance(ttl, bool) or ttl < 1:
                msg = "'ttl' must be a positive number of seconds"
                raise GrantError(msg, code="invalid-request")
        elif verb == "revoke":
            _check_keys(request, {"verb"}, {"id", "source", "address", "session"})
            if ("id" in request) == ("source" in request):
                msg = "revoke takes exactly one of 'id' and 'source'"
                raise GrantError(msg, code="invalid-request")
            if "address" in request and "source" not in request:
                msg = "revoke takes 'address' only with 'source'"
                raise GrantError(msg, code="invalid-request")
        elif verb == "list":
            _check_keys(request, {"verb"}, {"session"})
        elif verb in {"share-attach", "share-detach"}:
            _check_keys(request, {"verb", "guest", "share"}, {"session"})
        else:
            msg = (
                f"unknown verb {verb!r}; expected grant, revoke, list, share-attach,"
                " or share-detach"
            )
            raise GrantError(msg, code="invalid-request")
        return request

    def _grant(self, policy: Policy, request: Record, record: Callable[..., None]) -> Record:
        source, ttl = _string(request, "source"), cast("int", request["ttl"])
        target = Target.parse(_string(request, "target"))
        address = _optional_string(request, "address")
        interfaces = (
            policy.resolve_source(source, address)
            if self.read_text is None
            else policy.resolve_source(source, address, self.read_text)
        )
        max_ttl = policy.max_ttl(source, target)
        if ttl > max_ttl:
            msg = f"a TTL of {ttl}s exceeds the {max_ttl}s the policy allows {source} to {target}"
            raise GrantError(msg, code="ttl")
        paths = policy.paths(interfaces, target)
        with self.lock():
            live = self.kernel.elements()
            for element in live:
                if any(element.path.conflicts(path) for path in paths):
                    msg = (
                        f"{target} overlaps grant {element.grant} ({element.source} to"
                        f" {element.target}); revoke it first"
                    )
                    raise GrantError(msg, code="conflict")
            # By address, so renaming a source never resets its count.
            places = {(interface.network.bridge, interface.address) for interface in interfaces}
            held = {element.grant for element in live if element.path.place in places}
            macs = {path.place: path.mac for path in paths}
            moved = sorted(
                {e.grant for e in live if e.path.mac != macs.get(e.path.place, e.path.mac)}
            )
            if moved:
                msg = (
                    f"grants {', '.join(moved)} at this address belong to another MAC, an"
                    f" earlier holder of the lease; revoke them first"
                )
                raise GrantError(msg, code="conflict")
            if len(held) >= policy.max_concurrent:
                msg = f"{source} holds {len(held)} grants, the most the policy allows"
                raise GrantError(msg, code="max-concurrent")
            taken = {element.grant for element in live}
            grant = self.new_id()
            while grant in taken:
                grant = self.new_id()
            elements = [Element(path, grant, source, str(target), ttl) for path in paths]
            if len(elements[0].comment) > COMMENT_LIMIT:
                msg = f"{source} to {target} is too long a name pair for an element comment"
                raise GrantError(msg, code="invalid-target")
            record(
                "granted",
                f"granted {grant}: {source} to {target} for {ttl}s",
                grant=grant,
                source=source,
                target=str(target),
                ttl=ttl,
                address=interfaces[0].address,
                mac=interfaces[0].mac,
            )
            # Routes first: a failed add leaves only a route the forward chain still guards.
            self._sync_routes(policy, [*live, *elements])
            # The source stays as long as the longest grant it holds.
            # Listed expiries are whole seconds rounded down.
            same = [e.expires + 1 for e in live if e.path.place in places]
            self.kernel.add(elements, ttl, max([ttl, *same]))
        return {"grant": describe(elements)[0]}

    def _revoke(self, policy: Policy, request: Record, record: Callable[..., None]) -> Record:
        grant, source = _optional_string(request, "id"), _optional_string(request, "source")
        if grant is not None and ID_PATTERN.fullmatch(grant) is None:
            msg = f"'{grant}' is no grant id"
            raise GrantError(msg, code="invalid-request")
        if source is not None and not (
            SANDBOX_PATTERN.fullmatch(source) or source.startswith("guest:")
        ):
            msg = f"'{source}' is no source: expected sbx-<name> or guest:<name>"
            raise GrantError(msg, code="invalid-source")
        places: set[tuple[str, ipaddress.IPv4Address]] = set()
        address = _optional_string(request, "address")
        if source is not None and (address is not None or not SANDBOX_PATTERN.fullmatch(source)):
            interfaces = (
                policy.identify(source, address)
                if address is not None
                else policy.sources.get(source, ())
            )
            places = {(interface.network.bridge, interface.address) for interface in interfaces}
        with self.lock():
            live = self.kernel.elements()
            # A source's grants: those at its address, and those made under its name.
            chosen = [
                element
                for element in live
                if (
                    element.grant == grant
                    if grant is not None
                    else element.source == source or element.path.place in places
                )
            ]
            if grant is not None and not chosen:
                msg = f"no live grant {grant}"
                raise GrantError(msg, code="not-found")
            revoked = sorted({element.grant for element in chosen})
            record(
                "revoked",
                f"revoked {', '.join(revoked) or 'nothing'}",
                grant=",".join(revoked),
                source=source,
            )
            kept = [element for element in live if element not in chosen]
            held = {(e.path.place, e.path.mac) for e in kept}
            emptied = list(
                {
                    (e.path.place, e.path.mac): e.path
                    for e in chosen
                    if (e.path.place, e.path.mac) not in held
                }.values()
            )
            # Marked entries stay: deleting one lets the next segment open an unmarked one.
            self.kernel.remove(chosen, emptied)
            self._sync_routes(policy, kept)
        return {"revoked": revoked}

    def _share(self, policy: Policy, request: Record, record: Callable[..., None]) -> Record:
        guest = policy.share_guest(_string(request, "guest"))
        tag = _string(request, "share")
        declared = guest.shares.get(tag)
        attach = request["verb"] == "share-attach"
        with self.lock():
            if attach:
                read_only = self._attach(guest, tag, declared, record)
            else:
                read_only = self._detach(guest, tag, record)
        return {
            "share": {
                "guest": guest.name,
                "tag": tag,
                "read_only": read_only,
                "mount_point": None if declared is None else declared.mount_point,
                "attached": attach,
            }
        }

    def _attach(
        self,
        guest: ShareGuest,
        tag: str,
        share: RuntimeShare | None,
        record: Callable[..., None],
    ) -> bool:
        """Hot-plug a declared share's device file; return whether it is read-only."""
        place = f"guest:{guest.name}"
        if share is None:
            msg = f"{place} declares no runtime share '{tag}'; runtime = true marks one"
            raise GrantError(msg, code="not-declared")
        state = self.libvirt.state(guest.domain)
        if state != "running":
            msg = f"{place} is {state}; runtime shares attach to a running guest"
            raise GrantError(msg, code="not-running")
        if tag in self.libvirt.shares(guest.domain):
            msg = f"{place} already holds {tag}"
            raise GrantError(msg, code="already-attached")
        record(
            "attached",
            f"attached {tag} to {place}",
            guest=guest.name,
            share=tag,
            read_only=share.read_only,
        )
        self.libvirt.attach(guest.domain, share.device)
        return share.read_only

    def _detach(self, guest: ShareGuest, tag: str, record: Callable[..., None]) -> bool:
        """Detach any live share, declared or not, and wait until the device leaves."""
        place = f"guest:{guest.name}"
        state = self.libvirt.state(guest.domain)
        if state == "shut off" and self.libvirt.saved(guest.domain):
            msg = f"{place} is saved with its live shares; start it, then detach"
            raise GrantError(msg, code="saved")
        # A guest that is shut off holds no live device.
        live = None if state == "shut off" else self.libvirt.shares(guest.domain).get(tag)
        if live is None:
            msg = f"{place} holds no {tag}"
            raise GrantError(msg, code="not-attached")
        record(
            "detached",
            f"detached {tag} from {place}",
            guest=guest.name,
            share=tag,
            read_only=live.read_only,
        )
        self.libvirt.detach(guest.domain, live.alias)
        deadline = self.clock() + DETACH_WAIT
        while tag in self.libvirt.shares(guest.domain):
            if self.clock() >= deadline:
                msg = (
                    f"{place} still holds {tag} {DETACH_WAIT:g}s after the detach request;"
                    " the share stays usable until the guest releases it or stops"
                )
                raise GrantError(msg, code="detach-pending")
            self.sleep(DETACH_POLL)
        return live.read_only

    def _sync_routes(self, policy: Policy, elements: Sequence[Element]) -> None:
        """Routes of expired grants go too; until then the forward chain drops their traffic."""
        preference = policy.route_preference
        desired = {route for element in elements for route in policy.routes(element.path)}
        current = self.kernel.routes(preference)
        for route in sorted(current - desired):
            self.kernel.delete_route(preference, route)
        for route in sorted(desired - current):
            self.kernel.add_route(preference, route)


def _journal_field(key: str, value: str) -> bytes:
    data = value.encode()
    return key.encode() + b"\n" + struct.pack("<Q", len(data)) + data + b"\n"


def journal(message: str, fields: dict[str, object]) -> None:
    """Send one entry over journald's native protocol with WORKLOAD_GRANT_<KEY> fields."""
    entries = {"MESSAGE": message, "SYSLOG_IDENTIFIER": "workload-grant", "PRIORITY": "6"}
    entries |= {
        f"WORKLOAD_GRANT_{key.upper()}": str(value)
        for key, value in fields.items()
        if value is not None
    }
    payload = b"".join(_journal_field(key, value) for key, value in entries.items())
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
        sock.sendto(payload, JOURNAL_SOCKET)


def _cmdline(pid: int) -> str:
    try:
        raw = FilePath(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return "(exited)"
    return raw.replace(b"\0", b" ").decode(errors="replace").strip()[:512]


def _receive(connection: socket.socket) -> bytes:
    chunks: list[bytes] = []
    size = 0
    while chunk := connection.recv(4096):
        size += len(chunk)
        if size > REQUEST_LIMIT:
            msg = f"the request exceeds {REQUEST_LIMIT} bytes"
            raise GrantError(msg, code="invalid-request")
        chunks.append(chunk)
    return b"".join(chunks)


@contextlib.contextmanager
def file_lock(path: FilePath) -> Generator[None]:
    """Serialize instances: each request reads, decides, and writes under it."""
    with path.open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def main(policy_path: FilePath, tools: Tools, lock_path: FilePath) -> int:
    """Serve the connection systemd passes on stdin."""
    connection = socket.socket(fileno=os.dup(sys.stdin.fileno()))
    connection.settimeout(10)
    credentials = connection.getsockopt(
        socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")
    )
    pid, uid, _ = struct.unpack("3i", credentials)
    caller = Caller(pid, uid, _cmdline(pid))

    def load_policy() -> Policy:
        try:
            data: object = json.loads(policy_path.read_text())
        except (OSError, ValueError) as error:
            msg = f"cannot read {policy_path}: {error}"
            raise GrantError(msg, code="policy-file") from error
        return Policy.from_json(data)

    service = Service(
        load_policy,
        NftKernel(tools),
        journal,
        lambda: file_lock(lock_path),
        libvirt=Virsh(tools.virsh),
    )
    try:
        raw = _receive(connection)
    except TimeoutError:
        response: Record = {"error": {"code": "invalid-request", "message": "no request arrived"}}
    except GrantError as error:
        response = {"error": {"code": error.code, "message": str(error)}}
    else:
        response = service.handle(raw, caller)
    connection.sendall(json.dumps(response).encode() + b"\n")
    connection.close()
    return 0
