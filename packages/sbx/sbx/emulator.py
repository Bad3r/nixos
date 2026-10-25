# Copyright (c) 2026 Bad3r
"""QEMU launcher that confines a sandbox's vsock device to a private namespace.

vhost-vsock routes a guest's connections in the network namespace that opened
the device. In a namespace whose vsock mode is `local`, the guest reaches only
sockets in that namespace, so no host listener, whether it starts before or
after the guest, is reachable from it. libvirt opens the device in its own
namespace and passes the descriptor down, so the launcher replaces it.
"""

import os
import sys
from pathlib import Path
from typing import NoReturn

VHOST_VSOCK = "/dev/vhost-vsock"
FD_DIR = Path("/proc/self/fd")
NS_MODE = Path("/proc/sys/net/vsock/ns_mode")


class LaunchError(Exception):
    """A condition under which the sandbox must not start."""


def private_namespace(uid: int, gid: int) -> None:
    """Enter a new user and network namespace that maps only the caller."""
    os.unshare(os.CLONE_NEWUSER | os.CLONE_NEWNET)
    Path("/proc/self/setgroups").write_text("deny")
    Path("/proc/self/uid_map").write_text(f"{uid} {uid} 1\n")
    Path("/proc/self/gid_map").write_text(f"{gid} {gid} 1\n")


def check_local(mode_file: Path) -> None:
    """Refuse unless the current namespace keeps vsock to itself."""
    try:
        mode = mode_file.read_text().strip()
    except FileNotFoundError as error:
        msg = f"{mode_file} is missing; this kernel has no vsock namespaces"
        raise LaunchError(msg) from error
    if mode != "local":
        msg = f"the sandbox namespace's vsock mode is {mode}; net.vsock.child_ns_mode must be local"
        raise LaunchError(msg)


def vhost_vsock_fds(fd_dir: Path) -> list[int]:
    """Return the inherited descriptors open on the vhost-vsock device."""
    found: list[int] = []
    for entry in fd_dir.iterdir():
        try:
            target = str(entry.readlink())
        except FileNotFoundError:
            continue
        if target == VHOST_VSOCK:
            found.append(int(entry.name))
    return sorted(found)


def rebind(fds: list[int], device: str = VHOST_VSOCK) -> None:
    """Reopen each descriptor's device in the current namespace, at the same number."""
    for fd in fds:
        # The original keeps its CID reserved in the global pool, so CIDs stay unique.
        os.set_inheritable(os.dup(fd), True)  # noqa: FBT003
        fresh = os.open(device, os.O_RDWR)
        os.dup2(fresh, fd)
        os.close(fresh)


def main(emulator: str, argv: list[str]) -> NoReturn:
    """Start QEMU in a private local vsock namespace, or exit 1 without starting it."""
    fds = vhost_vsock_fds(FD_DIR)
    try:
        private_namespace(os.getuid(), os.getgid())
        check_local(NS_MODE)
        rebind(fds)
    except (LaunchError, OSError) as error:
        print(f"sbx-qemu: {error}", file=sys.stderr)
        sys.exit(1)
    os.execv(emulator, [emulator, *argv])  # noqa: S606
