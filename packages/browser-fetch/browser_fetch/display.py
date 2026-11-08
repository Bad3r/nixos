# Copyright (c) 2026 Bad3r
"""The user's X display, as browser-fetch login hands it to the namespaced browser.

The browser's network namespace cannot reach the X server's abstract socket,
so it gets the display's socket file bound into its private /tmp, and an
Xauthority file holding only that display's entries.
"""

from __future__ import annotations

import os
import re
import socket
import stat
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator, Mapping

# Xlib's socket directory (xtrans, X11_DISPLAY_PATH ... /tmp/.X11-unix/X<n>).
SOCKET_DIR = Path("/tmp/.X11-unix")  # noqa: S108 - the X server's fixed path
# Xauthority families (X11/Xauth.h).
FAMILY_LOCAL = 256
FAMILY_WILD = 65535
# A local display: ":N", ":N.S", or "unix:N", which Xlib reaches over the socket file.
_LOCAL = re.compile(r"(?:unix)?:(\d+)(?:\.(\d+))?")


class DisplayError(Exception):
    """There is no local X display the browser can open its window on."""


@dataclass(frozen=True)
class Display:
    """A local X display: its name for DISPLAY, its socket, and its Xauthority entries."""

    name: str
    socket: Path
    authority: bytes


@dataclass(frozen=True)
class AuthEntry:
    """One Xauthority record (libXau's Xauth)."""

    family: int
    address: bytes
    number: bytes
    name: bytes
    data: bytes

    def encode(self) -> bytes:
        """The record as XauWriteAuth writes it: a family, then four counted strings."""
        fields = (self.address, self.number, self.name, self.data)
        return struct.pack(">H", self.family) + b"".join(
            struct.pack(">H", len(field)) + field for field in fields
        )


def parse_authority(data: bytes) -> Iterator[AuthEntry]:
    """The records of an Xauthority file, in order; a truncated tail ends them, as XauReadAuth."""
    at = 0
    while at + 2 <= len(data):
        (family,) = struct.unpack_from(">H", data, at)
        at += 2
        fields: list[bytes] = []
        for _ in range(4):
            if at + 2 > len(data):
                return
            (length,) = struct.unpack_from(">H", data, at)
            at += 2
            if at + length > len(data):
                return
            fields.append(data[at : at + length])
            at += length
        yield AuthEntry(family, *fields)


def entries_for(data: bytes, number: int, hostname: str) -> bytes:
    """The records Xlib may use for local display number, as one Xauthority file.

    A connection over the socket file asks XauGetBestAuthByAddr for family
    FamilyLocal at the host's name: a record matches with that family and
    address or FamilyWild, and with the display's number or none.
    """
    wanted = str(number).encode()
    host = hostname.encode()
    return b"".join(
        entry.encode()
        for entry in parse_authority(data)
        if (entry.family == FAMILY_WILD or (entry.family == FAMILY_LOCAL and entry.address == host))
        and entry.number in {b"", wanted}
    )


def authority_file(environ: Mapping[str, str]) -> Path | None:
    """The Xauthority file Xlib reads (XauFileName): XAUTHORITY, else ~/.Xauthority."""
    named = environ.get("XAUTHORITY")
    if named:
        return Path(named)
    home = environ.get("HOME")
    return Path(home) / ".Xauthority" if home else None


def local_display(environ: Mapping[str, str]) -> Display:
    """The display DISPLAY names, which must be one on this machine's socket directory."""
    name = environ.get("DISPLAY", "")
    match = _LOCAL.fullmatch(name)
    if match is None:
        why = "DISPLAY is not set" if not name else f"DISPLAY={name} is not a local display"
        msg = f"the login window needs a local X display: {why}"
        raise DisplayError(msg)
    number = int(match.group(1))
    path = SOCKET_DIR / f"X{number}"
    try:
        is_socket = stat.S_ISSOCK(path.stat().st_mode)
    except OSError:
        is_socket = False
    if not is_socket:
        msg = f"the X display {name} has no socket at {path}"
        raise DisplayError(msg)
    authority = b""
    source = authority_file(environ)
    if source is not None:
        try:
            authority = entries_for(source.read_bytes(), number, socket.gethostname())
        except FileNotFoundError:
            authority = b""
        except OSError as error:
            msg = f"the X authority file {source} could not be read: {error.strerror}"
            raise DisplayError(msg) from None
    screen = f".{match.group(2)}" if match.group(2) is not None else ""
    return Display(f":{number}{screen}", path, authority)


def write_authority(path: Path, display: Display) -> None:
    """Write the display's entries to a new 0600 file."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(display.authority)
