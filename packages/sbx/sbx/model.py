# Copyright (c) 2026 Bad3r
"""Names, records, and the backend protocol every sbx module shares."""

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, Protocol

from sbx.errors import SbxError

if TYPE_CHECKING:
    from collections.abc import Sequence
    from pathlib import Path


NS = "https://github.com/Bad3r/nixos/sbx"
DOMAIN_PREFIX = "sbx-"
NAME_PATTERN = re.compile(r"[a-z0-9][a-z0-9-]{0,30}")
# Sandbox directories sit beside the base out-links.
RESERVED_NAMES = frozenset({"bases"})
FLAVOURS = ("nixos", "nixos-gui")
# Bases with a display that takes key and type input.
GUI_BASES = frozenset({"nixos-gui"})
NETS = ("none", "egress")
GIB = 1 << 30
TIMEOUT_EXIT = 124
# Holds the creation token of a run directory, which its domain metadata also carries.
CREATION_FILE = "creation"
# The run directory's read-write share; no host sbx code writes into it, unlike xfer.
SHARED = "shared"

ET.register_namespace("sbx", NS)


@dataclass(frozen=True)
class Meta:
    """What sbx records in a sandbox's domain metadata."""

    base: str
    image: str
    net: str
    created: int
    expires: int
    session: str | None
    # Names the call that created the sandbox, so its cleanup never hits a namesake.
    token: str | None = None

    def element(self) -> ET.Element:
        """Render the metadata element."""
        root = ET.Element(f"{{{NS}}}sandbox")
        values = {
            "base": self.base,
            "image": self.image,
            "net": self.net,
            "created": str(self.created),
            "expires": str(self.expires),
        }
        if self.session is not None:
            values["session"] = self.session
        if self.token is not None:
            values["token"] = self.token
        for key, value in values.items():
            ET.SubElement(root, f"{{{NS}}}{key}").text = value
        return root

    @classmethod
    def parse(cls, element: ET.Element) -> Meta:
        """Read the metadata element."""

        def text(key: str) -> str:
            value = element.findtext(f"{{{NS}}}{key}")
            if value is None:
                msg = f"sandbox metadata lacks {key}"
                raise SbxError(msg, code="metadata")
            return value

        return cls(
            base=text("base"),
            image=text("image"),
            net=text("net"),
            created=int(text("created")),
            expires=int(text("expires")),
            session=element.findtext(f"{{{NS}}}session"),
            token=element.findtext(f"{{{NS}}}token"),
        )


@dataclass(frozen=True)
class DomainInfo:
    """One session domain as the backend reports it."""

    name: str
    state: str
    active: bool
    memory_mib: int
    cpus: int
    cid: int | None
    meta: Meta | None
    managed_save: bool
    mac: str | None = None
    pid: int | None = None
    emulator: str | None = None


@dataclass(frozen=True)
class Sandbox:
    """A domain sbx created, with its metadata."""

    name: str
    domain: DomainInfo
    meta: Meta


@dataclass(frozen=True)
class ExecResult:
    """Outcome of one command in a sandbox."""

    exit_code: int | None
    stdout: bytes
    stderr: bytes
    truncated: bool
    timed_out: bool

    def as_json(self) -> dict[str, object]:
        """Return the JSON form."""
        return {
            "exit_code": self.exit_code,
            "stdout": self.stdout.decode(errors="replace"),
            "stderr": self.stderr.decode(errors="replace"),
            "truncated": self.truncated,
            "timed_out": self.timed_out,
        }


@dataclass(frozen=True)
class Request:
    """Validated parameters of a new sandbox."""

    base: str
    name: str | None
    net: str
    memory_mib: int
    cpus: int
    ttl: int
    # Seconds to queue for the running and memory ceilings; None refuses at once.
    wait: float | None = None


class Backend(Protocol):
    """Operations on the session daemon."""

    def domains(self) -> list[DomainInfo]:
        """List every session domain."""
        ...

    def domain(self, domain: str) -> DomainInfo | None:
        """Describe one domain, or return None when it does not exist."""
        ...

    def start(self, xml: str) -> None:
        """Define a persistent domain and start it."""
        ...

    def remove(self, domain: str) -> None:
        """Stop a domain if it runs and undefine it with its NVRAM and saved state."""
        ...

    def agent(self, domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:
        """Run one qemu-ga command and return its reply."""
        ...

    def screenshot(self, domain: str, target: Path) -> str:
        """Write the primary display to a file and return its MIME type."""
        ...

    def suspend(self, domain: str) -> None:
        """Pause a running domain."""
        ...

    def resume(self, domain: str) -> None:
        """Continue a paused domain."""
        ...

    def managed_save(self, domain: str) -> None:
        """Save an active domain's state and stop it."""
        ...

    def restore(self, domain: str) -> None:
        """Start a defined domain, from its managed save when it has one."""
        ...

    def set_time(self, domain: str) -> None:
        """Set the guest clock to the host's through qemu-ga."""
        ...

    def job_active(self, domain: str) -> bool:
        """Return whether a job, such as a managed save, runs on a domain."""
        ...

    def abort_job(self, domain: str) -> None:
        """Abort a domain's running job."""
        ...

    def send_key(self, domain: str, keycodes: Sequence[int], holdtime: int) -> None:
        """Press Linux keycodes together for `holdtime` ms, then release them."""
        ...
