# Copyright (c) 2026 Bad3r
"""Vsock grants: host services a sandbox without an address reaches over vsock.

workload-grantd decides and records them in a root-owned list; the owner's
`sbx-vsock` service reads the list and holds the listeners inside each
sandbox's QEMU namespace, so the helper never enters a namespace itself.
"""

import contextlib
import json
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path as FilePath
from typing import TYPE_CHECKING, Protocol, cast

from workloads.grants import GrantError, Ports, Record

if TYPE_CHECKING:
    from collections.abc import Sequence

# packages/sbx/sbx/vsock.py reads it.
STATE = FilePath("/run/workloads/vsock-grants.json")
# `sbx` creation tokens: secrets.token_hex(8).
TOKEN_PATTERN = re.compile(r"[0-9a-f]{16}")


def boottime() -> float:
    """Seconds since boot, host sleep included, so a TTL never pauses with the host."""
    return time.clock_gettime(time.CLOCK_BOOTTIME)


@dataclass(frozen=True)
class VsockGrant:
    """One grant: the sandbox creation it belongs to, its TCP ports, and its deadline."""

    grant: str
    source: str
    token: str
    target: str
    ports: tuple[Ports, ...]
    # CLOCK_BOOTTIME seconds.
    deadline: float
    # The service's `bind`, which picks the address the proxy connects to.
    bind: str

    def record(self) -> Record:
        """The list entry `sbx-vsock` reads."""
        return {
            "id": self.grant,
            "source": self.source,
            "token": self.token,
            "target": self.target,
            "ports": [{"from": port.first, "to": port.last} for port in self.ports],
            "deadline": self.deadline,
            "bind": self.bind,
        }

    @classmethod
    def parse(cls, entry: Record) -> VsockGrant:
        """Read one list entry."""
        return cls(
            str(entry["id"]),
            str(entry["source"]),
            str(entry["token"]),
            str(entry["target"]),
            tuple(
                Ports("tcp", int(cast("int", port["from"])), int(cast("int", port["to"])))
                for port in cast("list[Record]", entry["ports"])
            ),
            float(cast("float", entry["deadline"])),
            str(entry["bind"]),
        )

    def describe(self, now: float) -> Record:
        """The JSON form `workloads grants` prints."""
        return {
            "id": self.grant,
            "source": self.source,
            "target": self.target,
            "expires_in": max(0, round(self.deadline - now)),
            "paths": [
                {
                    "transport": "vsock",
                    "token": self.token,
                    "bind": self.bind,
                    "proto": port.proto,
                    "ports": port.text,
                }
                for port in self.ports
            ],
        }


class VsockStore(Protocol):
    """The vsock grant list."""

    def grants(self) -> list[VsockGrant]:
        """Every listed grant, expired ones included."""
        ...

    def write(self, grants: Sequence[VsockGrant]) -> None:
        """Replace the list."""
        ...


class FileStore:
    """The list as one JSON file, replaced atomically so a reader never sees half of it."""

    def __init__(self, path: FilePath = STATE) -> None:
        """Keep the path."""
        self.path = path

    def grants(self) -> list[VsockGrant]:
        """A missing file lists nothing."""
        try:
            data: object = json.loads(self.path.read_text())
        except FileNotFoundError:
            return []
        except (OSError, ValueError) as error:
            msg = f"cannot read {self.path}: {error}"
            raise GrantError(msg, code="vsock-list") from error
        try:
            return [
                VsockGrant.parse(entry)
                for entry in cast("list[Record]", cast("Record", data)["grants"])
            ]
        except (AttributeError, KeyError, TypeError, ValueError) as error:
            msg = f"{self.path} is malformed: {error!r}"
            raise GrantError(msg, code="vsock-list") from error

    def write(self, grants: Sequence[VsockGrant]) -> None:
        """World-readable, since the owner's proxy reads it; the helper's umask is 0077."""
        staged = self.path.with_name(f".{self.path.name}.{os.getpid()}")
        payload = json.dumps({"grants": [grant.record() for grant in grants]}).encode()
        try:
            fd = os.open(staged, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as handle:
                os.fchmod(fd, 0o644)
                handle.write(payload)
            staged.replace(self.path)
        except OSError as error:
            with contextlib.suppress(OSError):
                staged.unlink()
            msg = f"cannot write {self.path}: {error}"
            raise GrantError(msg, code="vsock-list") from error


def stream_ports(target: str, ports: Sequence[Ports]) -> tuple[Ports, ...]:
    """The TCP ranges of a grant; vsock carries streams only."""
    tcp = tuple(port for port in ports if port.proto == "tcp")
    if not tcp:
        msg = f"{target}: a sandbox without an address reaches TCP ports only, over vsock"
        raise GrantError(msg, code="not-grantable")
    return tcp
