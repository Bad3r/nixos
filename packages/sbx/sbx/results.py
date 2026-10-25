# Copyright (c) 2026 Bad3r
"""What sbx operations return: one JSON form each, shared by the CLI and MCP."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TYPE_CHECKING

from sbx.errors import SbxError, error_document

if TYPE_CHECKING:
    from collections.abc import Sequence


class Result(ABC):
    """An operation's outcome."""

    @abstractmethod
    def as_json(self) -> object:
        """Return the document `--json` prints and an MCP tool returns."""

    def exit_status(self) -> int:
        """Return the CLI's exit status."""
        return 0

    def error(self) -> SbxError | None:
        """Return the error of an outcome that still failed as a whole."""
        return None


@dataclass(frozen=True)
class Document(Result):
    """A result with no type of its own."""

    value: object
    code: int = 0

    def as_json(self) -> object:
        """Return the value as it is."""
        return self.value

    def exit_status(self) -> int:
        """Return the code the operation set."""
        return self.code


@dataclass(frozen=True)
class Results(Result):
    """A list of results."""

    items: Sequence[Result]

    def as_json(self) -> list[object]:
        """Return each item's JSON form."""
        return [item.as_json() for item in self.items]


@dataclass(frozen=True)
class SandboxView(Result):
    """One sandbox as list, info, and create describe it; info adds console, image, and shares."""

    name: str
    domain: str
    state: str
    base: str
    net: str
    cid: int | None
    address: str | None
    memory_mib: int
    cpus: int
    created: str
    expires: str
    ttl_left: int
    session: str | None
    token: str | None
    directory: str
    xfer: str
    console: str | None = None
    image: str | None = None
    shares: tuple[ShareView, ...] | None = None

    def as_json(self) -> dict[str, object]:
        """Return the fields, leaving out console and image outside info."""
        document: dict[str, object] = {
            "name": self.name,
            "domain": self.domain,
            "state": self.state,
            "base": self.base,
            "net": self.net,
            "cid": self.cid,
            "address": self.address,
            "memory_mib": self.memory_mib,
            "cpus": self.cpus,
            "created": self.created,
            "expires": self.expires,
            "ttl_left": self.ttl_left,
            "session": self.session,
            "token": self.token,
            "directory": self.directory,
            "xfer": self.xfer,
        }
        if self.console is not None:
            document["console"] = self.console
        if self.image is not None:
            document["image"] = self.image
        if self.shares is not None:
            document["shares"] = [share.as_json() for share in self.shares]
        return document


@dataclass(frozen=True)
class CopyResult(Result):
    """One copy between host and sandbox; a failed copy out of a run carries its error."""

    source: str
    target: str | None
    failure: SbxError | OSError | None = None

    def as_json(self) -> dict[str, object]:
        """Return {from, to}, or {from, error} for a failed copy."""
        if self.failure is not None:
            return {"from": self.source, "error": error_document(self.failure)}
        return {"from": self.source, "to": self.target}


@dataclass(frozen=True)
class ScreenshotResult(Result):
    """A saved capture of a sandbox display."""

    path: str
    mime: str
    text: str | None = None

    def as_json(self) -> dict[str, object]:
        """Return {path, mime}, with text when OCR ran."""
        document: dict[str, object] = {"path": self.path, "mime": self.mime}
        if self.text is not None:
            document["text"] = self.text
        return document


@dataclass(frozen=True)
class KeyResult(Result):
    """Chords pressed on a sandbox display."""

    sandbox: str
    keys: tuple[str, ...]

    def as_json(self) -> dict[str, object]:
        """Return {sandbox, keys}."""
        return {"sandbox": self.sandbox, "keys": list(self.keys)}


@dataclass(frozen=True)
class TypeResult(Result):
    """Text typed on a sandbox display; only its length is kept."""

    sandbox: str
    characters: int

    def as_json(self) -> dict[str, object]:
        """Return {sandbox, characters}."""
        return {"sandbox": self.sandbox, "characters": self.characters}


@dataclass(frozen=True)
class ShareView:
    """One share a sandbox holds; `mountpoint` is where the guest mounted it first."""

    tag: str
    read_only: bool
    host_path: str
    mountpoint: str | None = None

    def as_json(self) -> dict[str, object]:
        """Return {tag, read_only, host_path}, with mountpoint when the guest mounted it."""
        document: dict[str, object] = {
            "tag": self.tag,
            "read_only": self.read_only,
            "host_path": self.host_path,
        }
        if self.mountpoint is not None:
            document["mountpoint"] = self.mountpoint
        return document


@dataclass(frozen=True)
class GuestMount:
    """How an attached share is mounted in the guest, and whether it is."""

    mountpoint: str
    mounted: bool
    mount_command: str
    unmount_command: str
    error: str | None = None

    def as_json(self) -> dict[str, object]:
        """Return the fields, with mount_error when the mount failed."""
        document: dict[str, object] = {
            "mountpoint": self.mountpoint,
            "mounted": self.mounted,
            "mount_command": self.mount_command,
            "unmount_command": self.unmount_command,
        }
        if self.error is not None:
            document["mount_error"] = self.error
        return document


@dataclass(frozen=True)
class GuestUnmount:
    """The guest mounts a detach removed; `recovery` is set when the guest did not answer."""

    unmounted: tuple[str, ...]
    recovery: str | None = None

    def as_json(self) -> dict[str, object]:
        """Return {guest_unmounted, unmounted}, with recovery_command when it failed."""
        document: dict[str, object] = {
            "guest_unmounted": self.recovery is None,
            "unmounted": list(self.unmounted),
        }
        if self.recovery is not None:
            document["recovery_command"] = self.recovery
        return document


@dataclass(frozen=True)
class ShareResult(Result):
    """A share attached to or detached from a sandbox, with what the guest did about it."""

    sandbox: str
    tag: str
    read_only: bool
    host_path: str
    attached: bool
    guest: GuestMount | GuestUnmount | None = None

    def as_json(self) -> dict[str, object]:
        """Return the fields and the guest's part."""
        document: dict[str, object] = {
            "sandbox": self.sandbox,
            "tag": self.tag,
            "read_only": self.read_only,
            "host_path": self.host_path,
            "attached": self.attached,
        }
        if self.guest is not None:
            document |= self.guest.as_json()
        return document


@dataclass(frozen=True)
class GcAction(Result):
    """One thing gc removed or detached, or would under --dry-run."""

    name: str
    reason: str

    def as_json(self) -> dict[str, object]:
        """Return {name, reason}."""
        return {"name": self.name, "reason": self.reason}


@dataclass(frozen=True)
class MouseResult(Result):
    """The pointer moved on a sandbox display, and maybe clicked there."""

    sandbox: str
    x: int
    y: int
    click: str | None
    double: bool

    def as_json(self) -> dict[str, object]:
        """Return {sandbox, x, y, click, double}."""
        return {
            "sandbox": self.sandbox,
            "x": self.x,
            "y": self.y,
            "click": self.click,
            "double": self.double,
        }


@dataclass(frozen=True)
class Window:
    """One X window as the guest's xdotool describes it."""

    id: int
    name: str
    x: int
    y: int
    width: int
    height: int

    def as_json(self) -> dict[str, object]:
        """Return {id, name, geometry}."""
        geometry = {"x": self.x, "y": self.y, "width": self.width, "height": self.height}
        return {"id": self.id, "name": self.name, "geometry": geometry}


@dataclass(frozen=True)
class WindowsResult(Result):
    """Windows on a sandbox display."""

    sandbox: str
    windows: tuple[Window, ...]

    def as_json(self) -> dict[str, object]:
        """Return {sandbox, windows}."""
        return {"sandbox": self.sandbox, "windows": [window.as_json() for window in self.windows]}


@dataclass(frozen=True)
class FocusResult(Result):
    """The window a sandbox display focused."""

    sandbox: str
    window: Window

    def as_json(self) -> dict[str, object]:
        """Return {sandbox, window}."""
        return {"sandbox": self.sandbox, "window": self.window.as_json()}
