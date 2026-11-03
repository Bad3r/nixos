# Copyright (c) 2026 Bad3r
"""Record the SSH host keys of declared workload guests for the host's SSH client.

`capture` reads one guest's ED25519 public key through its QEMU guest agent,
which reaches the guest without the network, and stores it. `render` writes the
known_hosts file from the stored keys of the declared guests, drops the keys of
guests no longer declared, and queues a capture for each running guest.

A guest controls what its agent returns, so a key is accepted only as one
well-formed ED25519 key, and every known_hosts line is built here from the
declared hostnames and the decoded key bytes.
"""

import argparse
import base64
import binascii
import contextlib
import fcntl
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING

import libvirt
import libvirt_qemu

if TYPE_CHECKING:
    from collections.abc import Iterator

KEY_PATHS = {
    "windows": r"C:\ProgramData\ssh\ssh_host_ed25519_key.pub",
    "nixos": "/etc/ssh/ssh_host_ed25519_key.pub",
    "linux": "/etc/ssh/ssh_host_ed25519_key.pub",
}
KEY_TYPE = b"ssh-ed25519"
# A public key line is about 100 bytes; a larger file is not one.
MAX_KEY_FILE = 4096
AGENT_TIMEOUT = 30
POLL_SECONDS = 15
BASE64 = re.compile(r"[A-Za-z0-9+/]+={0,2}")


class KeyFormatError(ValueError):
    """A guest returned something other than one ED25519 public key."""


def log(message: str) -> None:
    """Print one journal line."""
    print(message, flush=True)


def parse_key(data: bytes) -> bytes:
    """Return the key blob of a single-line `ssh-ed25519 <base64> [comment]` file."""
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as error:
        msg = "the key file is not ASCII"
        raise KeyFormatError(msg) from error
    line = text.rstrip("\r\n")
    if not line or any(char in line for char in "\r\n\0"):
        msg = "the key file is not one line"
        raise KeyFormatError(msg)
    key_type, _, rest = line.partition(" ")
    encoded = rest.split(" ", 1)[0]
    if key_type != KEY_TYPE.decode() or not encoded:
        msg = "the key file holds no ssh-ed25519 key"
        raise KeyFormatError(msg)
    if not BASE64.fullmatch(encoded):
        msg = "the key is not base64"
        raise KeyFormatError(msg)
    try:
        blob = base64.b64decode(encoded, validate=True)
    except binascii.Error as error:
        msg = "the key is not base64"
        raise KeyFormatError(msg) from error
    return check_blob(blob)


def check_blob(blob: bytes) -> bytes:
    """Return the blob when it is exactly an ED25519 key in SSH wire format."""
    expected = struct.pack(">I", len(KEY_TYPE)) + KEY_TYPE + struct.pack(">I", 32)
    if len(blob) != len(expected) + 32 or not blob.startswith(expected):
        msg = "the key is not an ED25519 public key"
        raise KeyFormatError(msg)
    return blob


def fingerprint(blob: bytes) -> str:
    """Return the SHA256 fingerprint ssh-keygen -l prints."""
    return "SHA256:" + base64.b64encode(hashlib.sha256(blob).digest()).decode().rstrip("=")


def known_hosts_line(hostnames: list[str], blob: bytes) -> str:
    """Return one known_hosts line for the declared hostnames."""
    return f"{','.join(hostnames)} {KEY_TYPE.decode()} {base64.b64encode(blob).decode()}\n"


def write_atomic(path: Path, data: bytes, mode: int) -> None:
    """Replace a file so readers see the old or the new content, never a part."""
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fchmod(handle.fileno(), mode)
            os.fsync(handle.fileno())
        Path(temp).replace(path)
    except BaseException:
        Path(temp).unlink(missing_ok=True)
        raise


@contextlib.contextmanager
def locked(manifest_path: Path) -> Iterator[None]:
    """Hold the lock that serializes changes to the stored keys."""
    with Path(load(manifest_path)["keyDir"], ".lock").open("w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def render(manifest: dict) -> None:
    """Write known_hosts from the stored keys of declared guests; drop the rest."""
    key_dir = Path(manifest["keyDir"])
    guests = manifest["guests"]
    lines = []
    for stored in sorted(key_dir.glob("*.key")):
        name = stored.stem
        if name not in guests:
            stored.unlink()
            log(f"{name}: dropped the key of an undeclared guest")
            continue
        try:
            blob = check_blob(stored.read_bytes())
        except KeyFormatError as error:
            stored.unlink()
            log(f"{name}: dropped a stored key: {error}")
            continue
        lines.append(known_hosts_line(guests[name]["hostnames"], blob))
    write_atomic(Path(manifest["knownHosts"]), "".join(lines).encode(), 0o644)


def read_guest_file(domain: libvirt.virDomain, path: str) -> bytes:
    """Return a small guest file through the guest agent."""

    def call(command: str, **arguments: object) -> object:
        request = json.dumps({"execute": command, "arguments": arguments})
        return json.loads(libvirt_qemu.qemuAgentCommand(domain, request, AGENT_TIMEOUT, 0))[
            "return"
        ]

    handle = call("guest-file-open", path=path, mode="rb")
    data = b""
    try:
        # Windows reports the end only on the read after the last byte; an
        # empty read ends it too, so a guest cannot keep the loop spinning.
        while True:
            chunk = call("guest-file-read", handle=handle, count=MAX_KEY_FILE)
            piece = base64.b64decode(chunk["buf-b64"])  # type: ignore[index]
            data += piece
            if len(data) > MAX_KEY_FILE:
                msg = f"the key file is larger than {MAX_KEY_FILE} bytes"
                raise KeyFormatError(msg)
            if chunk["eof"] or not piece:  # type: ignore[index]
                return data
    finally:
        call("guest-file-close", handle=handle)


def load(path: Path) -> dict:
    """Read the manifest of the running system."""
    return json.loads(path.read_text())


def read_key(uuid: str, path: str) -> bytes:
    """Read one guest's host key over a fresh connection, which survives a libvirtd restart."""
    conn = libvirt.open("qemu:///system")
    try:
        return parse_key(read_guest_file(conn.lookupByUUIDString(uuid), path))
    finally:
        conn.close()


def capture(manifest_path: Path, name: str) -> None:
    """Wait for the guest's host key, then store it and render known_hosts."""
    waiting = None
    while True:
        # Re-read each round, so a switch while the guest is waiting takes effect.
        guest = load(manifest_path)["guests"].get(name)
        if guest is None:
            log(f"{name} is not a declared guest with a guest agent; nothing to record")
            return
        path = KEY_PATHS[guest["kind"]]
        try:
            blob = read_key(guest["uuid"], path)
            break
        except libvirt.libvirtError as error:
            reason = error.get_error_message()
        # A guest's reply is untrusted, so a malformed key never ends the wait.
        except (KeyFormatError, KeyError, TypeError, ValueError) as error:
            reason = f"unusable reply: {error}"
        if reason != waiting:
            log(f"{name}: waiting for {path}: {reason!r}")
            waiting = reason
        time.sleep(POLL_SECONDS)

    with locked(manifest_path):
        manifest = load(manifest_path)
        if name not in manifest["guests"]:
            log(f"{name}: undeclared while waiting; the key is not recorded")
            return
        stored = Path(manifest["keyDir"], f"{name}.key")
        previous = stored.read_bytes() if stored.exists() else None
        if previous != blob:
            write_atomic(stored, blob, 0o600)
            change = "recorded" if previous is None else "replaced the previous key with"
            log(f"{name}: {change} host key {fingerprint(blob)}")
        else:
            log(f"{name}: host key {fingerprint(blob)} unchanged")
        render(manifest)


def refresh(manifest_path: Path, systemctl: str, unit: str) -> None:
    """Render known_hosts, then queue a capture for each running declared guest."""
    with locked(manifest_path):
        manifest = load(manifest_path)
        render(manifest)
    conn = libvirt.open("qemu:///system")
    try:
        for name, guest in sorted(manifest["guests"].items()):
            try:
                running = conn.lookupByUUIDString(guest["uuid"]).isActive()
            except libvirt.libvirtError:
                running = False
            if running:
                subprocess.run(
                    [systemctl, "--no-block", "start", unit.replace("%i", name)], check=True
                )
    finally:
        conn.close()


def main() -> None:
    """Parse arguments and run one command."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("capture").add_argument("guest")
    refresh_parser = commands.add_parser("refresh")
    refresh_parser.add_argument("systemctl")
    refresh_parser.add_argument("unit")
    args = parser.parse_args()
    # Errors are caught and logged once per change; the default handler prints each to stderr.
    libvirt.registerErrorHandler(lambda _ctx, _error: None, None)
    if args.command == "capture":
        capture(args.manifest, args.guest)
    else:
        refresh(args.manifest, args.systemctl, args.unit)


if __name__ == "__main__":
    try:
        main()
    except (OSError, libvirt.libvirtError, subprocess.CalledProcessError) as error:
        print(f"workloads-host-keys: {error}", file=sys.stderr)
        sys.exit(1)
