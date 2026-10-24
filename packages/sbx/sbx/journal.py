# Copyright (c) 2026 Bad3r
"""Journal entries for sbx verbs, sent over journald's native protocol."""

import socket
import struct
import sys

SOCKET = "/run/systemd/journal/socket"


class _State:
    warned = False


def _field(key: str, value: str) -> bytes:
    data = value.encode()
    return key.encode() + b"\n" + struct.pack("<Q", len(data)) + data + b"\n"


def record(message: str, **fields: object) -> None:
    """Send one entry tagged SYSLOG_IDENTIFIER=sbx with SBX_<KEY> fields."""
    entries = {"MESSAGE": message, "SYSLOG_IDENTIFIER": "sbx", "PRIORITY": "6"}
    entries |= {
        f"SBX_{key.upper()}": str(value) for key, value in fields.items() if value is not None
    }
    payload = b"".join(_field(key, value) for key, value in entries.items())
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.sendto(payload, SOCKET)
    except OSError as error:
        if not _State.warned:
            print(f"sbx: cannot write to the journal: {error}", file=sys.stderr)
            _State.warned = True
