# Copyright (c) 2026 Bad3r
"""QEMU launcher that confines a sandbox's vsock device to a private namespace.

vhost-vsock routes a guest's connections in the network namespace that opened
the device. In a namespace whose vsock mode is `local`, the guest reaches only
sockets in that namespace, so no host listener, whether it starts before or
after the guest, is reachable from it. libvirt opens the device in its own
namespace and passes the descriptor down, so the launcher replaces it.

Only the standard library may be imported: the wrapper's store path is pinned
in every sandbox definition and save image, so it is built from this file alone.
"""

import itertools
import json
import os
import stat
import sys
from pathlib import Path
from typing import NoReturn, cast

VHOST_VSOCK = "/dev/vhost-vsock"
FD_DIR = Path("/proc/self/fd")
NS_MODE = Path("/proc/sys/net/vsock/ns_mode")


class LaunchError(Exception):
    """A condition under which the sandbox must not start."""


def private_namespace(uid: int, gid: int) -> None:
    """Enter a new user and network namespace that maps only the caller."""
    try:
        os.unshare(os.CLONE_NEWUSER | os.CLONE_NEWNET)
    except OSError as error:
        msg = f"cannot create a user and network namespace: {error.strerror}"
        raise LaunchError(msg) from error
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


def device_fds(fd_dir: Path, device: str) -> list[int]:
    """Return the inherited descriptors open on the character device at `device`."""
    try:
        rdev = Path(device).stat().st_rdev
    except FileNotFoundError:
        return []
    found: list[int] = []
    for entry in fd_dir.iterdir():
        try:
            info = os.fstat(int(entry.name))
        except OSError:
            # The listing's own descriptor is closed by now.
            continue
        if stat.S_ISCHR(info.st_mode) and info.st_rdev == rdev:
            found.append(int(entry.name))
    return sorted(found)


def vsock_devices(argv: list[str]) -> list[dict[str, object]]:
    """Return the properties of every vhost-vsock `-device` on QEMU's command line."""
    devices: list[dict[str, object]] = []
    for flag, value in itertools.pairwise(argv):
        if flag not in {"-device", "--device"} or "vhost-vsock" not in value:
            continue
        try:
            properties = json.loads(value)
        except json.JSONDecodeError as error:
            msg = f"cannot read the vsock device {value!r}; only JSON device options are handled"
            raise LaunchError(msg) from error
        if not isinstance(properties, dict):
            msg = f"the vsock device {value!r} is not a JSON object"
            raise LaunchError(msg)
        devices.append(cast("dict[str, object]", properties))
    return devices


def check_vhostfds(argv: list[str], rebound: list[int]) -> None:
    """Refuse unless vsock devices and inherited vhost-vsock descriptors pair up one to one."""
    used: list[int] = []
    for device in vsock_devices(argv):
        fd = device.get("vhostfd")
        if not (isinstance(fd, str) and fd.isdigit() and int(fd) in rebound):
            msg = (
                f"vsock device {device.get('id')} takes vhostfd {fd!r}, "
                "not a descriptor sbx-qemu reopens in the sandbox namespace"
            )
            raise LaunchError(msg)
        used.append(int(fd))
    if unused := sorted(set(rebound) - set(used)):
        msg = f"inherited vhost-vsock descriptors {unused} back no vsock device on the command line"
        raise LaunchError(msg)


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
    try:
        fds = device_fds(FD_DIR, VHOST_VSOCK)
        check_vhostfds(argv, fds)
        private_namespace(os.getuid(), os.getgid())
        check_local(NS_MODE)
        rebind(fds)
    except (LaunchError, OSError) as error:
        print(f"sbx-qemu: {error}", file=sys.stderr)
        sys.exit(1)
    os.execv(emulator, [emulator, *argv])  # noqa: S606
