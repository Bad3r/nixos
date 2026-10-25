# Copyright (c) 2026 Bad3r
"""Launchers that confine a sandbox's QEMU and swtpm before they start.

Each runs in a new user, network, and mount namespace. The mount namespace's
root holds the store read-only, a few character devices, and only the files and
directories its command line names, so an escaped emulator reaches no other
host path, socket, or block device.

vhost-vsock routes a guest's connections in the network namespace that opened
the device. In a namespace whose vsock mode is `local`, the guest reaches only
sockets in that namespace, so no host listener, whether it starts before or
after the guest, is reachable from it. libvirt opens the device in its own
namespace and passes the descriptor down, so the launcher replaces it.

Only the standard library may be imported: the wrapper's store path is pinned
in every sandbox definition and save image, so it is built from this file alone.
"""

import ctypes
import itertools
import json
import os
import socket
import stat
import sys
from pathlib import Path
from typing import Literal, NamedTuple, NoReturn, cast

VHOST_VSOCK = "/dev/vhost-vsock"
FD_DIR = Path("/proc/self/fd")
NS_MODE = Path("/proc/sys/net/vsock/ns_mode")
STORE = "/nix/store"
LOCALTIME = "/etc/localtime"
# QEMU gets its vhost, tap, monitor, and log descriptors from libvirt, so it opens no other device.
DEVICES = ("/dev/full", "/dev/kvm", "/dev/null", "/dev/random", "/dev/urandom", "/dev/zero")

MS_RDONLY = 0x1
MS_NOSUID = 0x2
MS_NODEV = 0x4
MS_NOEXEC = 0x8
MS_REMOUNT = 0x20
MS_NOATIME = 0x400
MS_NODIRATIME = 0x800
MS_BIND = 0x1000
MS_REC = 0x4000
MS_PRIVATE = 0x40000
MS_SLAVE = 0x80000
MS_RELATIME = 0x200000
MNT_DETACH = 0x2
# statvfs flag to mount flag; a bind remount in a user namespace must keep the locked ones.
LOCKED_FLAGS = (
    (os.ST_NOSUID, MS_NOSUID),
    (os.ST_NODEV, MS_NODEV),
    (os.ST_NOEXEC, MS_NOEXEC),
    (os.ST_NOATIME, MS_NOATIME),
    (os.ST_NODIRATIME, MS_NODIRATIME),
    (os.ST_RELATIME, MS_RELATIME),
)
SYS_PIVOT_ROOT = {"x86_64": 155, "aarch64": 41}

type Kind = Literal["dir", "file", "socket", "device"]
KINDS: dict[Kind, int] = {
    "dir": stat.S_IFDIR,
    "file": stat.S_IFREG,
    "socket": stat.S_IFSOCK,
    "device": stat.S_IFCHR,
}


class LaunchError(Exception):
    """A condition under which the sandbox must not start."""


class Bind(NamedTuple):
    """A host path that appears at the same path inside the confined root."""

    path: str
    writable: bool
    kind: Kind


def private_namespace(uid: int, gid: int) -> None:
    """Enter a new user, network, and mount namespace that maps only the caller."""
    try:
        os.unshare(os.CLONE_NEWUSER | os.CLONE_NEWNET | os.CLONE_NEWNS)
    except OSError as error:
        msg = f"cannot create a user, network, and mount namespace: {error.strerror}"
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


def _json_object(flag: str, value: str) -> dict[str, object]:
    try:
        parsed: object = json.loads(value)
    except json.JSONDecodeError as error:
        msg = f"cannot read the {flag} {value!r}; only JSON options are handled"
        raise LaunchError(msg) from error
    if not isinstance(parsed, dict):
        msg = f"the {flag} {value!r} is not a JSON object"
        raise LaunchError(msg)
    return cast("dict[str, object]", parsed)


def vsock_devices(argv: list[str]) -> list[dict[str, object]]:
    """Return the properties of every vhost-vsock `-device` on QEMU's command line."""
    return [
        _json_object("vsock device", value)
        for flag, value in itertools.pairwise(argv)
        if flag in {"-device", "--device"} and "vhost-vsock" in value
    ]


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


def fields(value: str) -> list[str]:
    """Split a QEMU-style comma list, where a doubled comma is a literal one."""
    result: list[str] = []
    current: list[str] = []
    index = 0
    while index < len(value):
        if value[index] != ",":
            current.append(value[index])
        elif value[index + 1 : index + 2] == ",":
            current.append(",")
            index += 1
        else:
            result.append("".join(current))
            current = []
        index += 1
    result.append("".join(current))
    return result


def options(value: str) -> dict[str, str]:
    """Return the `key=value` fields of a comma list; a bare field maps to the empty string."""
    return dict(
        (field.split("=", 1)[0], field.split("=", 1)[1]) if "=" in field else (field, "")
        for field in fields(value)
    )


def _directory(path: str) -> str:
    return str(Path(os.path.normpath(path)).parent)


def _block_binds(argv: list[str]) -> list[Bind]:
    """Return each `-blockdev` file, read-only when it or every format node atop it is."""
    files: dict[object, tuple[str, bool]] = {}
    readers: dict[object, list[bool]] = {}
    for flag, value in itertools.pairwise(argv):
        if flag != "-blockdev":
            continue
        node = _json_object("block device", value)
        filename, read_only = node.get("filename"), node.get("read-only") is True
        if isinstance(filename, str):
            files[node.get("node-name")] = (filename, read_only)
        elif "file" in node:
            readers.setdefault(node["file"], []).append(read_only)
    return [
        Bind(filename, not read_only and not all(readers.get(node, [False])), "file")
        for node, (filename, read_only) in files.items()
        if not filename.startswith("/dev/fdset/")
    ]


def _chardev_binds(value: str) -> list[Bind]:
    backend = fields(value)[0]
    path = options(value).get("path")
    if path is None or path.startswith("/dev/fdset/"):
        return []
    if backend == "socket":
        return [Bind(path, writable=True, kind="socket")]
    if backend == "file":
        return [Bind(path, writable=True, kind="file")]
    msg = f"the {backend} chardev path {path!r} is not handled"
    raise LaunchError(msg)


def _option_binds(flag: str, value: str) -> list[Bind]:
    """Return the paths one command-line option names, outside block devices."""
    if flag == "-object" and value.startswith("{"):
        properties = _json_object("object", value)
        key = properties.get("file")
        if properties.get("qom-type") == "secret" and isinstance(key, str):
            # libvirt's domain directory, where screendumps, the SPICE socket, and
            # hot-plugged virtiofs sockets appear after QEMU starts.
            return [Bind(_directory(key), writable=True, kind="dir")]
    elif flag == "-chardev":
        return _chardev_binds(value)
    elif flag == "-spice":
        spice = options(value)
        if spice.get("unix") == "on" and "addr" in spice:
            return [Bind(_directory(spice["addr"]), writable=True, kind="dir")]
    elif flag == "-qmp" and value.startswith("unix:"):
        path = fields(value.removeprefix("unix:"))[0]
        return [Bind(_directory(path), writable=True, kind="dir")]
    elif flag == "-pidfile":
        return [Bind(_directory(value), writable=True, kind="dir")]
    return []


def qemu_binds(argv: list[str]) -> list[Bind]:
    """Return the paths QEMU opens itself, from the command line libvirt gives it."""
    binds = [bind for pair in itertools.pairwise(argv) for bind in _option_binds(*pair)]
    binds += _block_binds(argv)
    if Path(LOCALTIME).exists():
        binds.append(Bind(LOCALTIME, writable=False, kind="file"))
    return binds


def _tpmstate_binds(found: dict[str, str]) -> list[Bind]:
    if "dir" in found:
        return [Bind(found["dir"], writable=True, kind="dir")]
    uri = found.get("backend-uri", "")
    if uri.startswith("file://"):
        return [Bind(uri.removeprefix("file://"), writable=True, kind="file")]
    if uri.startswith("dir://"):
        return [Bind(uri.removeprefix("dir://"), writable=True, kind="dir")]
    msg = f"the TPM state {found!r} is not handled"
    raise LaunchError(msg)


def swtpm_binds(argv: list[str]) -> list[Bind]:
    """Return the paths swtpm opens itself, besides the `--ctrl` socket `listen_ctrl` opens."""
    binds: list[Bind] = []
    for flag, value in itertools.pairwise(argv):
        found = options(value)
        if flag == "--tpmstate":
            binds += _tpmstate_binds(found)
        elif flag in {"--server", "--pid"} and ({"path", "file"} & found.keys()):
            # Its directory would hold every sandbox's swtpm socket.
            msg = f"swtpm {flag} {value!r} names a path; only descriptors are handled"
            raise LaunchError(msg)
        elif flag == "--log" and "file" in found:
            binds.append(Bind(found["file"], writable=True, kind="file"))
        elif flag in {"--key", "--migration-key"} and "file" in found:
            binds.append(Bind(found["file"], writable=False, kind="file"))
    return binds


def listen(path: str, mode: int) -> int:
    """Listen on a unix socket at `path`, replacing only a stale socket; return it inheritable."""
    try:
        existing: int | None = os.lstat(path).st_mode
    except FileNotFoundError:
        existing = None
    if existing is not None:
        if not stat.S_ISSOCK(existing):
            msg = f"{path} exists and is not a socket"
            raise LaunchError(msg)
        Path(path).unlink()
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    previous = os.umask(0o177)
    try:
        server.bind(path)
    finally:
        os.umask(previous)
    Path(path).chmod(mode)
    server.listen()
    fd = server.detach()
    os.set_inheritable(fd, True)  # noqa: FBT003
    return fd


def listen_ctrl(argv: list[str]) -> list[str]:
    """Return `argv` with each `--ctrl` socket path replaced by a descriptor listening on it.

    The socket's directory holds every sandbox's swtpm socket, so it stays out of swtpm's root.
    """
    result = list(argv)
    for index, (flag, value) in enumerate(itertools.pairwise(argv)):
        found = options(value)
        if flag != "--ctrl" or "path" not in found:
            continue
        if found.get("type") != "unixio" or not found.keys() <= {"type", "path", "mode"}:
            msg = f"swtpm --ctrl {value!r} is not handled"
            raise LaunchError(msg)
        fd = listen(found["path"], int(found.get("mode", "0770"), 8))
        result[index + 1] = f"type=unixio,fd={fd}"
    return result


def plan(binds: list[Bind]) -> list[Bind]:
    """Order binds parents first, dropping those a bound directory already holds."""
    normal: dict[str, Bind] = {}
    for bind in binds:
        if not Path(bind.path).is_absolute():
            msg = f"{bind.path!r} is not an absolute path"
            raise LaunchError(msg)
        path = os.path.normpath(bind.path)
        seen = normal.get(path)
        if seen is not None and seen.kind != bind.kind:
            msg = f"{path} is named both as a {seen.kind} and as a {bind.kind}"
            raise LaunchError(msg)
        writable = bind.writable or (seen is not None and seen.writable)
        normal[path] = Bind(path, writable, bind.kind)
    kept: list[Bind] = []
    for path in sorted(normal):
        if not any(path.startswith(parent.path.rstrip("/") + "/") for parent in kept):
            kept.append(normal[path])
    return kept


def _in_store(path: str) -> bool:
    return path == STORE or path.startswith(STORE + "/")


def _open_nofollow(path: str) -> int:
    """Open `path` as an `O_PATH` descriptor, refusing a symlink in any component."""
    fd = os.open("/", os.O_PATH | os.O_DIRECTORY)
    walked = Path("/")
    for part in Path(path).parts[1:]:
        walked /= part
        try:
            child = os.open(part, os.O_PATH | os.O_NOFOLLOW, dir_fd=fd)
        finally:
            os.close(fd)
        fd = child
        if stat.S_ISLNK(os.fstat(fd).st_mode):
            os.close(fd)
            msg = f"{path} passes through the symlink {walked}"
            raise LaunchError(msg)
    return fd


def open_source(bind: Bind) -> int | None:
    """Open a bind's source as an `O_PATH` descriptor, or return None when the host lacks it.

    Only a read-only source resolves symlinks, and only into the store, which the
    root holds read-only anyway.
    """
    path = bind.path
    if not bind.writable and _in_store(resolved := os.path.realpath(path)):
        path = resolved
    try:
        fd = _open_nofollow(path)
    except FileNotFoundError:
        return None
    if stat.S_IFMT(os.fstat(fd).st_mode) != KINDS[bind.kind]:
        os.close(fd)
        msg = f"{bind.path} is not a {bind.kind}"
        raise LaunchError(msg)
    return fd


_LIBC = ctypes.CDLL(None, use_errno=True)


def _encoded(value: str | None) -> bytes | None:
    return None if value is None else value.encode()


def _check(result: object, action: str) -> None:
    if result != 0:
        error = ctypes.get_errno()
        msg = f"cannot {action}: {os.strerror(error)}"
        raise LaunchError(msg)


def _mount(
    source: str | None, target: str, fstype: str | None, flags: int, data: str | None = None
) -> None:
    result = _LIBC.mount(
        _encoded(source), _encoded(target), _encoded(fstype), ctypes.c_ulong(flags), _encoded(data)
    )
    _check(result, f"mount {target}")


def _umount(target: str) -> None:
    _check(_LIBC.umount2(_encoded(target), MNT_DETACH), f"unmount {target}")


def _pivot_root(new_root: str, put_old: str) -> None:
    machine = os.uname().machine
    if (number := SYS_PIVOT_ROOT.get(machine)) is None:
        msg = f"no pivot_root syscall number for {machine}"
        raise LaunchError(msg)
    result = _LIBC.syscall(ctypes.c_long(number), _encoded(new_root), _encoded(put_old))
    _check(result, f"pivot into {new_root}")


def mount_bind(source: str, target: str, *, writable: bool, directory: bool) -> None:
    """Bind `source` at `target`, read-only unless `writable`."""
    if directory:
        Path(target).mkdir(parents=True, exist_ok=True)
    else:
        Path(target).parent.mkdir(parents=True, exist_ok=True)
        Path(target).touch(0o600, exist_ok=False)
    _mount(source, target, None, MS_BIND | MS_REC)
    if not writable:
        current = os.statvfs(target).f_flag
        locked = sum(flag for vfs, flag in LOCKED_FLAGS if current & vfs)
        _mount(None, target, None, MS_REMOUNT | MS_BIND | MS_RDONLY | locked)


def confine(binds: list[Bind]) -> None:
    """Pivot into a fresh read-only root that holds the store, the devices, and `binds` only.

    The caller has just entered a user and mount namespace of its own. Paths a
    command line names but the host lacks stay out, so the emulator fails on them.
    """
    wanted = plan(
        [
            Bind(STORE, writable=False, kind="dir"),
            *(Bind(device, writable=True, kind="device") for device in DEVICES),
            *binds,
        ]
    )
    sources: list[tuple[Bind, int]] = []
    try:
        sources.extend((bind, fd) for bind in wanted if (fd := open_source(bind)) is not None)
        _pivot(sources)
    finally:
        for _, fd in sources:
            os.close(fd)


def _pivot(sources: list[tuple[Bind, int]]) -> None:
    _mount(None, "/", None, MS_REC | MS_SLAVE)
    # A tmpfs over /tmp in this namespace only: the staging root for both pivots.
    staging = Path("/tmp")  # noqa: S108
    _mount("tmpfs", str(staging), "tmpfs", MS_NOSUID | MS_NODEV, "mode=0700")
    os.chdir(staging)
    Path("newroot").mkdir()
    Path("oldroot").mkdir()
    _mount("tmpfs", "newroot", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755")
    _pivot_root(".", "oldroot")
    os.chdir("/")
    for bind, fd in sources:
        # Through the descriptor, so the inode checked is the inode bound.
        mount_bind(
            f"/oldroot/proc/self/fd/{fd}",
            "/newroot" + bind.path,
            writable=bind.writable,
            directory=bind.kind == "dir",
        )
    _mount(None, "/oldroot", None, MS_REC | MS_PRIVATE)
    _umount("/oldroot")
    old = os.open("/", os.O_DIRECTORY | os.O_RDONLY)
    os.chdir("/newroot")
    _pivot_root(".", ".")
    os.fchdir(old)
    os.close(old)
    _umount(".")
    os.chdir("/")
    _mount(None, "/", None, MS_REMOUNT | MS_BIND | MS_RDONLY | MS_NOSUID | MS_NODEV)


def main(emulator: str, argv: list[str]) -> NoReturn:
    """Start QEMU confined in a private local vsock namespace, or exit 1 without starting it."""
    try:
        fds = device_fds(FD_DIR, VHOST_VSOCK)
        check_vhostfds(argv, fds)
        binds = qemu_binds(argv)
        private_namespace(os.getuid(), os.getgid())
        check_local(NS_MODE)
        rebind(fds)
        confine(binds)
    except (LaunchError, OSError) as error:
        print(f"sbx-qemu: {error}", file=sys.stderr)
        sys.exit(1)
    os.execv(emulator, [emulator, *argv])  # noqa: S606


def swtpm_main(swtpm: str, argv: list[str]) -> NoReturn:
    """Start swtpm confined like QEMU, without a host network, or exit 1 without starting it."""
    try:
        binds = swtpm_binds(argv)
        argv = listen_ctrl(argv)
        private_namespace(os.getuid(), os.getgid())
        confine(binds)
    except (LaunchError, OSError) as error:
        print(f"sbx-swtpm: {error}", file=sys.stderr)
        sys.exit(1)
    os.execv(swtpm, [swtpm, *argv])  # noqa: S606
