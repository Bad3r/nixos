# Copyright (c) 2026 Bad3r
"""Policy, ceilings, and lifecycle of sbx sandboxes.

Nothing here accepts domain XML or host disk paths: the domain comes from one
template, disks from a built base, and every resource value is checked
against the settings the app module renders.
"""

import base64
import binascii
import contextlib
import ctypes
import dataclasses
import errno
import fcntl
import json
import os
import re
import resource
import secrets
import shlex
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import IO, TYPE_CHECKING, Any, Protocol, cast

from sbx import cloud, journal, keys, waitqueue, windows
from sbx.cloud import CloudImage

if TYPE_CHECKING:
    from collections.abc import Callable, Generator, Sequence

    from sbx.windows import WindowsSettings

NS = "https://github.com/Bad3r/nixos/sbx"
DOMAIN_PREFIX = "sbx-"
# workload-grantd's socket; modules/workloads/sharing/grants.nix declares it.
GRANT_SOCKET = Path("/run/workloads/grant.sock")
NAME_PATTERN = re.compile(r"[a-z0-9][a-z0-9-]{0,30}")
# Sandbox directories sit beside the base out-links.
RESERVED_NAMES = frozenset({"bases"})
FLAVOURS = ("nixos", "nixos-gui")
# Bases with a display that takes key and type input.
GUI_BASES = frozenset({"nixos-gui"})
NETS = ("none", "egress")
SYS_NET = Path("/sys/class/net")
IFF_UP = 0x1
# systemd-tmpfiles writes /root/.ssh/authorized_keys from this credential.
CREDENTIAL = "opt/io.systemd.credentials/ssh.authorized_keys.root"
GIB = 1 << 30
DURATION_PATTERN = re.compile(r"(\d+)([smhd]?)")
MEMORY_PATTERN = re.compile(r"(\d+)([MG]?)", re.IGNORECASE)
DURATION_UNITS = {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}
SESSION_VARIABLES = (("CLAUDE_CODE_SESSION_ID", "claude"), ("CODEX_THREAD_ID", "codex"))
READ_CHUNK = 1 << 16
# Grace for the guest's `timeout --kill-after`, and the host backstop beyond it.
GUEST_KILL_AFTER = 5
HOST_BACKSTOP = GUEST_KILL_AFTER + 5
TIMEOUT_EXIT = 124
WATCH_INTERVAL = 0.5
AT_FDCWD = -100
RENAME_NOREPLACE = 1
# Holds the creation token of a run directory, which its domain metadata also carries.
CREATION_FILE = "creation"
KEY_HOLD_MS = 10
# At 20 to 40 ms a character, the longest text `type` takes runs under three minutes.
TYPE_LIMIT = 4096
# The prepare boot's lifetime must outlast its provisioning timeout.
PREPARE_TTL = 3600
PREPARE_TIMEOUT = 1800
SHUTDOWN_TIMEOUT = 120
# Runtime shares one sandbox can hold at once.
SHARE_SLOTS = 4
# The run directory's read-write share; no host sbx code writes into it, unlike xfer.
SHARED = "shared"
WAIT_POLL = 2.0
# The `--wait` an over-limit refusal suggests.
RETRY_WAIT = "30m"

ET.register_namespace("sbx", NS)


class SbxError(Exception):
    """A request sbx refuses or cannot complete."""

    def __init__(
        self, message: str, *, code: str, details: dict[str, object] | None = None
    ) -> None:
        """Keep a stable error code, and fields for the JSON error object, next to the message."""
        super().__init__(message)
        self.code = code
        self.details = details or {}


def error_document(error: SbxError | OSError) -> dict[str, object]:
    """Return the JSON error object of a failed verb."""
    if isinstance(error, SbxError):
        return {"code": error.code, "message": str(error), **error.details}
    return {"code": "os-error", "message": str(error)}


@dataclass(frozen=True)
class Tools:
    """Absolute paths of the programs sbx runs."""

    emulator: str
    qemu_img: str
    ssh: str
    scp: str
    ssh_keygen: str
    socat: str
    tesseract: str
    nsenter: str
    git: str
    systemctl: str
    nix: str
    nix_store: str
    timedatectl: str
    xorriso: str
    virtiofsd: str


@dataclass(frozen=True)
class Egress:
    """The bridge `--net egress` attaches to, the lease file of its DHCP server, and its MTU."""

    bridge: str
    leases: Path
    mtu: int


@dataclass(frozen=True)
class Settings:
    """Ceilings, defaults, and tool paths rendered by the app module."""

    running: int
    memory_mib: int
    sandbox_memory_mib: int
    sandbox_cpus: int
    max_ttl: int
    disk_cap_bytes: int
    min_free_bytes: int
    default_memory_mib: int
    default_gui_memory_mib: int
    default_cpus: int
    default_ttl: int
    disk_gib: int
    cpuset: str
    flake: str
    unit: str
    slice: str
    output_limit: int
    boot_timeout: int
    # Why `--net egress` is unavailable, when it is.
    egress: Egress | str
    cloud_images: dict[str, CloudImage]
    tools: Tools
    # Present when the host exports Windows bases.
    windows: WindowsSettings | None = None
    # The session daemon's file size limit, which every Windows overlay reserves.
    file_bytes: int = 0
    # Fixed copy roots beside $TMPDIR, which agent shells narrow to a per-session dir.
    copy_roots: tuple[Path, ...] = ()

    @classmethod
    def load(cls, path: Path) -> Settings:
        """Read the JSON settings file."""
        raw = json.loads(path.read_text())
        if "limits" not in raw:
            msg = "sbx has no settings; enable programs.sbx.extended"
            raise SbxError(msg, code="unconfigured")
        limits = raw["limits"]
        defaults = raw["defaults"]
        return cls(
            running=limits["running"],
            memory_mib=limits["memoryMiB"],
            sandbox_memory_mib=limits["sandboxMemoryMiB"],
            sandbox_cpus=limits["sandboxCpus"],
            max_ttl=limits["ttlSeconds"],
            disk_cap_bytes=limits["diskBytes"],
            min_free_bytes=limits["minFreeBytes"],
            default_memory_mib=defaults["memoryMiB"],
            default_gui_memory_mib=defaults["guiMemoryMiB"],
            default_cpus=defaults["cpus"],
            default_ttl=defaults["ttlSeconds"],
            disk_gib=defaults["diskGiB"],
            cpuset=raw["cpuset"],
            flake=raw["flake"],
            unit=raw["unit"],
            slice=raw["slice"],
            output_limit=raw["outputLimit"],
            boot_timeout=raw["bootTimeout"],
            egress=raw["egress"]
            if isinstance(raw["egress"], str)
            else Egress(
                raw["egress"]["bridge"], Path(raw["egress"]["leases"]), raw["egress"]["mtu"]
            ),
            cloud_images={
                name: CloudImage(image["url"], image["hash"])
                for name, image in raw["cloudImages"].items()
            },
            tools=Tools(**raw["tools"]),
            windows=None
            if raw["windows"] is None
            else windows.WindowsSettings.load(raw["windows"]),
            file_bytes=limits["fileBytes"],
            copy_roots=tuple(Path(root) for root in raw["copyRoots"]),
        )


@dataclass(frozen=True)
class Paths:
    """Where sandbox state lives."""

    root: Path
    config: Path

    @classmethod
    def from_environment(cls) -> Paths:
        """Follow the XDG base directories."""
        home = Path.home()
        data = os.environ.get("XDG_DATA_HOME") or str(home / ".local" / "share")
        config = os.environ.get("XDG_CONFIG_HOME") or str(home / ".config")
        return cls(Path(data) / "sbx", Path(config))

    @property
    def bases(self) -> Path:
        """Out-links of built bases, which double as GC roots."""
        return self.root / "bases"

    @property
    def lock(self) -> Path:
        """Serializes ceiling checks against starts and removals."""
        return self.root / ".lock"

    @property
    def queue(self) -> Path:
        """Tickets of creates that wait for capacity."""
        return self.root / ".queue"

    def sandbox(self, name: str) -> Path:
        """Return the run directory of one sandbox."""
        return self.root / name

    def sandbox_dirs(self) -> list[Path]:
        """List local sandbox directories without connecting to libvirt."""
        if not self.root.is_dir():
            return []
        return sorted(
            entry
            for entry in self.root.iterdir()
            if entry.is_dir()
            and not entry.is_symlink()
            and entry.name not in RESERVED_NAMES
            and NAME_PATTERN.fullmatch(entry.name) is not None
        )


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


def parse_duration(value: str) -> int:
    """Parse `90`, `90s`, `30m`, `2h`, or `1d` into seconds."""
    match = DURATION_PATTERN.fullmatch(value.strip())
    if match is None:
        msg = f"'{value}' is not a duration such as 30m, 2h, or 1d"
        raise SbxError(msg, code="invalid-argument")
    return int(match.group(1)) * DURATION_UNITS[match.group(2)]


def parse_memory(value: str) -> int:
    """Parse `2G`, `512M`, or a bare MiB count into MiB."""
    match = MEMORY_PATTERN.fullmatch(value.strip())
    if match is None:
        msg = f"'{value}' is not a memory size such as 512M or 2G"
        raise SbxError(msg, code="invalid-argument")
    amount = int(match.group(1))
    return amount * 1024 if match.group(2).upper() == "G" else amount


def remote_name(argument: str) -> str | None:
    """Return the sandbox name of an endpoint, allowing an empty guest path."""
    name, separator, _path = argument.partition(":")
    return name if separator and NAME_PATTERN.fullmatch(name) is not None else None


def caller_session() -> str | None:
    """Return the agent session that runs sbx, if any."""
    for variable, client in SESSION_VARIABLES:
        value = os.environ.get(variable)
        if value:
            return f"{client}:{value}"
    return None


def run(argv: Sequence[str]) -> str:
    """Run a helper and return its stdout, failing with its stderr."""
    result = subprocess.run(argv, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        msg = f"{Path(argv[0]).name} exited {result.returncode}: {result.stderr.strip()}"
        raise SbxError(msg, code="command-failed")
    return result.stdout


def _drain(stream: IO[bytes], limit: int, sink: list[tuple[bytes, bool]]) -> None:
    data = bytearray()
    truncated = False
    while chunk := stream.read(READ_CHUNK):
        room = limit - len(data)
        if room > 0:
            data += chunk[:room]
        if len(chunk) > room:
            truncated = True
    sink.append((bytes(data), truncated))


def capture(argv: Sequence[str], limit: int, timeout: float | None) -> ExecResult:
    """Run a command with closed stdin, keeping at most `limit` bytes per stream."""
    out: list[tuple[bytes, bool]] = []
    err: list[tuple[bytes, bool]] = []
    with subprocess.Popen(
        argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ) as process:
        if process.stdout is None or process.stderr is None:
            msg = "subprocess pipes are missing"
            raise SbxError(msg, code="internal")
        readers = [
            threading.Thread(target=_drain, args=(process.stdout, limit, out)),
            threading.Thread(target=_drain, args=(process.stderr, limit, err)),
        ]
        for reader in readers:
            reader.start()
        timed_out = False
        try:
            code = process.wait(timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            timed_out = True
            code = None
        for reader in readers:
            reader.join()
    return ExecResult(code, out[0][0], err[0][0], out[0][1] or err[0][1], timed_out)


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, UTC).isoformat(timespec="seconds")


def _within(path: Path, roots: Sequence[Path]) -> bool:
    return any(path.is_relative_to(root) for root in roots)


def _agent_error(detail: str) -> SbxError:
    msg = f"qemu-ga sent an unexpected reply: {detail}"
    return SbxError(msg, code="agent-reply")


def _agent_return(reply: dict[str, Any]) -> dict[str, Any]:
    value = reply.get("return")
    if not isinstance(value, dict):
        msg = "no return object"
        raise _agent_error(msg)
    return cast("dict[str, Any]", value)


def _agent_int(status: dict[str, Any], key: str) -> int | None:
    value = status.get(key)
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool):
        msg = f"{key} is not an integer"
        raise _agent_error(msg)
    return value


def _agent_data(status: dict[str, Any], key: str) -> bytes:
    value = status.get(key, "")
    if not isinstance(value, str):
        msg = f"{key} is not a string"
        raise _agent_error(msg)
    try:
        return base64.b64decode(value, validate=True)
    except binascii.Error as error:
        msg = f"{key} is not base64"
        raise _agent_error(msg) from error


def guest_command(command: Sequence[str], timeout: float | None) -> list[str]:
    """Bound a guest command by coreutils timeout, so it dies with the host's deadline."""
    if timeout is None:
        return list(command)
    return ["timeout", f"--kill-after={GUEST_KILL_AFTER}", f"{timeout:g}", *command]


def _backstop(timeout: float | None) -> float | None:
    return None if timeout is None else timeout + HOST_BACKSTOP


def _allocated(path: Path) -> int:
    total = 0
    for parent, _dirs, files in os.walk(path):
        for file in files:
            with contextlib.suppress(FileNotFoundError):
                total += (Path(parent) / file).lstat().st_blocks * 512
    return total


def _rename_noreplace(source: Path, target: Path) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = libc.renameat2
    renameat2.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    renameat2.restype = ctypes.c_int
    if renameat2(AT_FDCWD, os.fsencode(source), AT_FDCWD, os.fsencode(target), RENAME_NOREPLACE):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(target))


def _remove(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def _reopen_shared(directory: Path) -> None:
    """Give the owner search and read on every directory under shared again.

    A running guest may swap a directory for a link at any time, so each one is
    opened without following links and changed through its descriptor.
    """
    # One open descriptor per level, with the names left to visit in it.
    levels: list[tuple[int | None, list[str]]] = [(None, [str(directory / SHARED)])]
    try:
        while levels:
            parent, names = levels[-1]
            if not names:
                levels.pop()
                if parent is not None:
                    os.close(parent)
                continue
            try:
                handle = os.open(
                    names.pop(), os.O_PATH | os.O_NOFOLLOW | os.O_DIRECTORY, dir_fd=parent
                )
            except FileNotFoundError, NotADirectoryError:
                continue
            try:
                info = os.fstat(handle)
                if not stat.S_ISDIR(info.st_mode):
                    continue
                proc = Path(f"/proc/self/fd/{handle}")
                if info.st_mode & stat.S_IRWXU != stat.S_IRWXU:
                    proc.chmod(stat.S_IMODE(info.st_mode) | stat.S_IRWXU)
                listing = os.open(proc, os.O_RDONLY | os.O_DIRECTORY)
            finally:
                os.close(handle)
            try:
                children = [e.name for e in os.scandir(listing) if e.is_dir(follow_symlinks=False)]
            except OSError:
                os.close(listing)
                raise
            levels.append((listing, children))
    finally:
        for parent, _names in levels:
            if parent is not None:
                os.close(parent)


def _remove_run_directory(directory: Path) -> None:
    """Remove a run directory after reopening the shared directories a guest closed."""
    _reopen_shared(directory)
    shutil.rmtree(directory)


def publish(staged: Path, target: Path) -> None:
    """Move a staged copy to a target that must not exist, never replacing one."""
    try:
        try:
            _rename_noreplace(staged, target)
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            # Another filesystem: copy beside the target, then rename there.
            beside = target.with_name(f".sbx-{secrets.token_hex(4)}")
            try:
                if staged.is_dir():
                    shutil.copytree(staged, beside, symlinks=True)
                else:
                    shutil.copy2(staged, beside, follow_symlinks=False)
                _rename_noreplace(beside, target)
            finally:
                _remove(beside)
    except OSError as error:
        if error.errno == errno.EEXIST:
            msg = f"{target} exists; copies out never overwrite"
            raise SbxError(msg, code="exists") from error
        raise


@contextlib.contextmanager
def _terminate_raises() -> Generator[None]:
    """Turn SIGTERM into SystemExit in the main thread, so cleanups run as on SIGINT."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return

    def terminate(signum: int, _frame: object) -> None:
        raise SystemExit(128 + signum)

    previous = signal.signal(signal.SIGTERM, terminate)
    try:
        yield
    finally:
        signal.signal(signal.SIGTERM, previous)


def _strip_exec_bits(path: Path) -> None:
    """Drop execute, setuid, and setgid bits from every file under a copied-out path."""
    files = (
        [path]
        if not path.is_dir()
        else [Path(parent) / file for parent, _dirs, names in os.walk(path) for file in names]
    )
    for file in files:
        info = file.lstat()
        if stat.S_ISREG(info.st_mode):
            file.chmod(stat.S_IMODE(info.st_mode) & 0o666)


def random_mac() -> str:
    """Return a random address in QEMU's locally administered prefix."""
    return "52:54:00:" + ":".join(f"{byte:02x}" for byte in secrets.token_bytes(3))


def _lease_error(path: Path, detail: str) -> SbxError:
    msg = f"{path} is not a libvirt lease file: {detail}"
    return SbxError(msg, code="lease-file")


def revoke_grants(name: str, address: str | None) -> None:
    """End the workload grants of a removed sandbox; without the helper there are none."""
    request: dict[str, object] = {"verb": "revoke", "source": DOMAIN_PREFIX + name}
    if address is not None:
        request["address"] = address
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(30)
            connection.connect(str(GRANT_SOCKET))
            connection.sendall(json.dumps(request).encode())
            connection.shutdown(socket.SHUT_WR)
            answer = b"".join(iter(lambda: connection.recv(65536), b""))
    except FileNotFoundError:
        return
    except OSError as error:
        msg = f"workload-grantd is unreachable: {error}"
        raise SbxError(msg, code="grants") from error
    try:
        parsed: object = json.loads(answer)
    except json.JSONDecodeError as error:
        msg = f"workload-grantd answered no JSON: {error}"
        raise SbxError(msg, code="grants") from error
    if not isinstance(parsed, dict) or "revoked" not in parsed:
        msg = f"workload-grantd refused the revoke: {answer.decode(errors='replace').strip()}"
        raise SbxError(msg, code="grants")


def lease_address(path: Path, mac: str, now: float) -> str | None:
    """Return the IPv4 address the bridge's DHCP server leased to `mac`, if any."""
    mac = mac.lower()
    try:
        text = path.read_text()
    except FileNotFoundError:
        return None
    if not text.strip():
        return None
    try:
        leases = json.loads(text)
    except json.JSONDecodeError as error:
        raise _lease_error(path, str(error)) from error
    if not isinstance(leases, list):
        raise _lease_error(path, "not a list")
    best: tuple[float, str] | None = None
    for lease in cast("list[object]", leases):
        if not isinstance(lease, dict):
            raise _lease_error(path, "an entry is not an object")
        entry = cast("dict[str, object]", lease)
        address, owner, expiry = (
            entry.get("ip-address"),
            entry.get("mac-address"),
            entry.get("expiry-time"),
        )
        if not (isinstance(address, str) and isinstance(owner, str) and isinstance(expiry, int)):
            raise _lease_error(path, "an entry lacks ip-address, mac-address, or expiry-time")
        # libvirt's own reading: an expiry of 0 or below never expires.
        if owner.lower() != mac or ":" in address or 0 < expiry < now:
            continue
        rank = float("inf") if expiry <= 0 else float(expiry)
        if best is None or rank > best[0]:
            best = (rank, address)
    return None if best is None else best[1]


def guest_holds(reply: dict[str, Any], mac: str, address: str) -> bool:
    """Whether a guest-network-get-interfaces reply puts `address` on the NIC with `mac`."""
    interfaces = reply.get("return")
    if not isinstance(interfaces, list):
        msg = "no interface list"
        raise _agent_error(msg)
    for interface in cast("list[object]", interfaces):
        if not isinstance(interface, dict):
            msg = "an interface is not an object"
            raise _agent_error(msg)
        entry = cast("dict[str, object]", interface)
        owner = entry.get("hardware-address")
        if not isinstance(owner, str) or owner.lower() != mac.lower():
            continue
        addresses = entry.get("ip-addresses", [])
        if not isinstance(addresses, list):
            msg = "ip-addresses is not a list"
            raise _agent_error(msg)
        for item in cast("list[object]", addresses):
            if (
                isinstance(item, dict)
                and cast("dict[str, object]", item).get("ip-address") == address
            ):
                return True
    return False


def bridge_interface(bridge: str, mac: str) -> ET.Element:
    """Render a virtio NIC on a host bridge; session libvirt joins it through qemu-bridge-helper."""
    interface = ET.Element("interface", type="bridge")
    ET.SubElement(interface, "mac", address=mac)
    ET.SubElement(interface, "source", bridge=bridge)
    ET.SubElement(interface, "model", type="virtio")
    # No <mtu>: session libvirt cannot set a tap's MTU, so guests take it from DHCP or the seed.
    return interface


class Sandboxes:
    """Every sbx verb, over one backend."""

    def __init__(
        self,
        settings: Settings,
        paths: Paths,
        connect: Callable[[bool], Backend],
        session: str | None,
        clock: Callable[[], float] = time.time,
    ) -> None:
        """Bind settings and paths; the backend connects on first use."""
        self.settings = settings
        self.paths = paths
        self.session = session
        self._connect = connect
        self._clock = clock
        self._backend: Backend | None = None
        # Polled while a create waits; the MCP server ends the wait of a cancelled call.
        self.cancelled: Callable[[], bool] = lambda: False

    # Plumbing

    def backend(self, *, require_slice: bool = False) -> Backend:
        """Connect once; starting a guest requires the daemon in sbx.slice."""
        if self._backend is None or require_slice:
            self._backend = self._connect(require_slice)
        return self._backend

    def adopt(self, backend: Backend) -> None:
        """Use a backend connected some other way, such as without starting the daemon."""
        self._backend = backend

    @contextlib.contextmanager
    def locked(self, timeout: float | None = None) -> Generator[None]:
        """Hold the state lock, waiting up to `timeout`; flock is per open file: never nest it."""
        self.paths.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with self.paths.lock.open("a") as handle:
            if timeout is None:
                fcntl.flock(handle, fcntl.LOCK_EX)
            else:
                deadline = time.monotonic() + timeout
                while True:
                    try:
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        if time.monotonic() >= deadline:
                            msg = f"another sbx command held {self.paths.lock} for {timeout:g} s"
                            raise SbxError(msg, code="busy") from None
                        time.sleep(0.2)
            yield

    def _check_name(self, name: str) -> None:
        if NAME_PATTERN.fullmatch(name) is None or name in RESERVED_NAMES:
            msg = f"'{name}' is not a sandbox name: 1-31 of a-z, 0-9, and -, not 'bases'"
            raise SbxError(msg, code="invalid-name")

    def windows_base(self, base: str) -> WindowsSettings | None:
        """Return the Windows settings when `base` is a Windows base."""
        settings = self.settings.windows
        return settings if settings is not None and base in settings.bases else None

    def agent_only(self, name: str, *, token: str | None = None) -> bool:
        """Return whether a sandbox takes commands through qemu-ga only, as Windows does."""
        return self.windows_base(self.created(name, token).meta.base) is not None

    def _bases(self) -> list[str]:
        windows_bases = [] if self.settings.windows is None else list(self.settings.windows.bases)
        return [*FLAVOURS, *self.settings.cloud_images, *windows_bases]

    def has_state(self) -> bool:
        """Return whether any sandbox may exist, without starting the daemon."""
        definitions = self.paths.config / "libvirt" / "qemu"
        return bool(self.paths.sandbox_dirs()) or any(definitions.glob(f"{DOMAIN_PREFIX}*.xml"))

    def owned(self) -> list[Sandbox]:
        """Return the domains sbx created."""
        return [
            Sandbox(domain.name.removeprefix(DOMAIN_PREFIX), domain, domain.meta)
            for domain in self.backend().domains()
            if domain.meta is not None and domain.name.startswith(DOMAIN_PREFIX)
        ]

    def find(self, name: str) -> Sandbox:
        """Return one sandbox by name."""
        self._check_name(name)
        for sandbox in self.owned():
            if sandbox.name == name:
                return sandbox
        msg = f"no sandbox named '{name}'"
        raise SbxError(msg, code="not-found")

    def created(self, name: str, token: str | None) -> Sandbox:
        """Return a sandbox by name, refusing one another create made under that name."""
        sandbox = self.find(name)
        if token is not None and sandbox.meta.token != token:
            msg = f"sandbox '{name}' was destroyed and its name reused"
            raise SbxError(msg, code="replaced")
        return sandbox

    def describe(self, sandbox: Sandbox) -> dict[str, object]:
        """Return the JSON form of one sandbox."""
        domain, meta = sandbox.domain, sandbox.meta
        directory = self.paths.sandbox(sandbox.name)
        return {
            "name": sandbox.name,
            "domain": domain.name,
            "state": domain.state,
            "base": meta.base,
            "net": meta.net,
            "cid": domain.cid,
            "address": self.address(sandbox),
            "memory_mib": domain.memory_mib,
            "cpus": domain.cpus,
            "created": _iso(meta.created),
            "expires": _iso(meta.expires),
            "ttl_left": max(0, meta.expires - int(self._clock())),
            "session": meta.session,
            "token": meta.token,
            "directory": str(directory),
            "xfer": str(directory / "xfer"),
        }

    def address(self, sandbox: Sandbox, *, strict: bool = False) -> str | None:
        """Return the address of a running egress sandbox from the host's DHCP leases.

        A malformed lease file raises only when `strict`; otherwise it is logged
        and the address left out, so one bad file never fails a listing.
        """
        egress = self.settings.egress
        mac = sandbox.domain.mac
        if isinstance(egress, str) or mac is None or not sandbox.domain.active:
            return None
        try:
            return lease_address(egress.leases, mac, self._clock())
        except SbxError as error:
            if strict or error.code != "lease-file":
                raise
            journal.record(f"no address for {sandbox.name}: {error}", code=error.code)
            return None

    # Policy checks

    def _check_egress(self) -> Egress:
        """Return the egress bridge, refusing when it is not declared, absent, or down."""
        egress = self.settings.egress
        if isinstance(egress, str):
            raise SbxError(egress, code="egress-unavailable")
        device = SYS_NET / egress.bridge
        absent = f"bridge {egress.bridge} does not exist; its libvirt network is not running"
        if not (device / "bridge").is_dir():
            raise SbxError(absent, code="egress-unavailable")
        try:
            flags = int((device / "flags").read_text(), 16)
        except FileNotFoundError as error:
            raise SbxError(absent, code="egress-unavailable") from error
        if not flags & IFF_UP:
            msg = f"bridge {egress.bridge} is down"
            raise SbxError(msg, code="egress-unavailable")
        return egress

    def request(  # noqa: PLR0913
        self,
        base: str,
        *,
        name: str | None,
        net: str,
        memory: str | None,
        cpus: int | None,
        ttl: str | None,
        gui: bool = False,
        wait: str | None = None,
    ) -> Request:
        """Turn create flags into a request within the ceilings; `gui` picks `<base>-gui`."""
        settings = self.settings
        if gui and base not in GUI_BASES:
            if f"{base}-gui" not in GUI_BASES:
                msg = f"base '{base}' has no GUI variant; GUI bases: {', '.join(sorted(GUI_BASES))}"
                raise SbxError(msg, code="unknown-base")
            base = f"{base}-gui"
        windows_settings = self.windows_base(base)
        if windows_settings is not None:
            default_memory = windows_settings.memory_mib
        elif base in GUI_BASES:
            default_memory = settings.default_gui_memory_mib
        else:
            default_memory = settings.default_memory_mib
        request = Request(
            base,
            name,
            net,
            default_memory if memory is None else parse_memory(memory),
            settings.default_cpus if cpus is None else cpus,
            settings.default_ttl if ttl is None else parse_duration(ttl),
            None if wait is None else parse_duration(wait),
        )
        self._validate(request)
        return request

    def _validate(self, request: Request) -> None:
        settings = self.settings
        if request.base not in self._bases():
            msg = f"unknown base '{request.base}'; bases: {', '.join(self._bases())}"
            raise SbxError(msg, code="unknown-base")
        # Clones share the golden copy's SIDs, which stay harmless only off the network.
        if self.windows_base(request.base) is not None and request.net != "none":
            msg = "Windows bases run without a network"
            raise SbxError(msg, code="invalid-argument")
        if request.name is not None:
            self._check_name(request.name)
        if request.net not in NETS:
            msg = f"network '{request.net}' is not available; networks: {', '.join(NETS)}"
            raise SbxError(msg, code="invalid-argument")
        if not 256 <= request.memory_mib <= settings.sandbox_memory_mib:  # noqa: PLR2004
            msg = f"memory must be 256M to {settings.sandbox_memory_mib}M"
            raise SbxError(msg, code="over-limit")
        if not 1 <= request.cpus <= settings.sandbox_cpus:
            msg = f"cpus must be 1 to {settings.sandbox_cpus}"
            raise SbxError(msg, code="over-limit")
        if not 60 <= request.ttl <= settings.max_ttl:  # noqa: PLR2004
            msg = f"ttl must be 1m to {settings.max_ttl // 3600}h"
            raise SbxError(msg, code="over-limit")
        # The MCP tool timeout is the longest TTL, which must also cover the boot.
        longest_wait = settings.max_ttl - settings.boot_timeout
        if request.wait is not None and request.wait > longest_wait:
            msg = (
                f"wait must be at most {longest_wait // 60}m, the longest TTL less the boot timeout"
            )
            raise SbxError(msg, code="over-limit")

    def _usage(self) -> int:
        """Bytes under every run directory; a directory that cannot be read raises."""

        def unreadable(error: OSError) -> None:
            if not isinstance(error, FileNotFoundError):
                raise error

        total = 0
        for directory in self.paths.sandbox_dirs():
            _reopen_shared(directory)
            for parent, _dirs, files in os.walk(directory, onerror=unreadable):
                for file in files:
                    with contextlib.suppress(FileNotFoundError):
                        total += (Path(parent) / file).lstat().st_blocks * 512
        return total

    def disk_problem(self, reserve: int = 0) -> str | None:
        """Say why usage plus `reserve` passes the free-space floor or the cap, if it does."""
        self.paths.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        stats = os.statvfs(self.paths.root)
        free = stats.f_bavail * stats.f_frsize
        if free < self.settings.min_free_bytes:
            return (
                f"{self.paths.root} has {free // GIB}G free, "
                f"below the {self.settings.min_free_bytes // GIB}G floor"
            )
        try:
            used = self._usage()
        except OSError as error:
            return f"sandbox usage cannot be measured, so the cap counts as passed: {error}"
        if used + reserve > self.settings.disk_cap_bytes:
            return (
                f"sandboxes use {used // GIB}G and need {reserve // GIB}G more of the "
                f"{self.settings.disk_cap_bytes // GIB}G cap; destroy some or run `sbx gc`"
            )
        return None

    def check_disk(self, reserve: int = 0) -> None:
        """Refuse below the free-space floor or when usage plus `reserve` passes the cap."""
        problem = self.disk_problem(reserve)
        if problem is not None:
            raise SbxError(problem, code="disk-full")

    def _holders(self) -> list[Sandbox]:
        """Return the sandboxes that take a slot: running ones and those a managed save holds."""
        return [
            sandbox
            for sandbox in self.owned()
            if sandbox.domain.active or sandbox.domain.managed_save
        ]

    def _capacity_problem(self, request: Request) -> str | None:
        """Say why the running or memory ceiling leaves no room for `request`, if one does."""
        running = [sandbox.domain for sandbox in self._holders()]
        if len(running) >= self.settings.running:
            return f"{len(running)} sandboxes run, the ceiling is {self.settings.running}"
        declared = sum(domain.memory_mib for domain in running)
        if declared + request.memory_mib > self.settings.memory_mib:
            return (
                f"running sandboxes declare {declared}M; {request.memory_mib}M more exceeds "
                f"the {self.settings.memory_mib}M ceiling"
            )
        return None

    def _capacity_error(self, problem: str, ahead: int, *, code: str) -> SbxError:
        """Name who holds the capacity and, for over-limit, how to get it."""
        now = int(self._clock())
        running = self._holders()
        held = ", ".join(
            f"{sandbox.name} ({sandbox.meta.session or 'no session'}, "
            f"{max(0, sandbox.meta.expires - now) // 60}m left)"
            for sandbox in running
        )
        msg = f"{problem}; held by {held or 'no sbx sandbox'}"
        if ahead:
            msg += f"; {ahead} queued ahead"
        details: dict[str, object] = {
            "holders": [
                {
                    "name": sandbox.name,
                    "session": sandbox.meta.session,
                    "memory_mib": sandbox.domain.memory_mib,
                    "ttl_left": max(0, sandbox.meta.expires - now),
                }
                for sandbox in running
            ],
            "waiting": ahead,
        }
        if code == "over-limit":
            msg += (
                f". Rerun the same command with --wait {RETRY_WAIT} (MCP: wait) in the "
                "background and check back, or destroy your own idle sandboxes with "
                "`sbx destroy --mine`"
            )
            details["retry"] = {"wait": RETRY_WAIT}
        return SbxError(msg, code=code, details=details)

    def _ahead(self, ticket: waitqueue.Ticket | None) -> list[waitqueue.Ticket]:
        """Return the live tickets older than `ticket`, or every one for a new request."""
        queue = waitqueue.live(self.paths.queue)
        return [entry for entry in queue if ticket is None or entry.seq < ticket.seq]

    def _enqueue(
        self, request: Request, name: str, problem: str, position: int, deadline: float
    ) -> waitqueue.Ticket:
        # Waiting never clears a disk limit already passed.
        self.check_disk()
        ticket = waitqueue.enqueue(
            self.paths.queue,
            name=name,
            base=request.base,
            memory_mib=request.memory_mib,
            session=self.session,
            queued=int(self._clock()),
            deadline=deadline,
        )
        journal.record(
            f"{name} queues for capacity at position {position}: {problem}",
            verb="create",
            sandbox=name,
            session=self.session,
        )
        print(f"sbx: {name} queues at position {position}: {problem}", file=sys.stderr)
        return ticket

    def _dequeue(self, ticket: waitqueue.Ticket | None, started: float | None) -> None:
        """Drop a ticket; with `started`, its create proceeds, which the journal records."""
        if ticket is None or not ticket.path.exists():
            return
        ticket.path.unlink(missing_ok=True)
        if started is not None:
            journal.record(
                f"{ticket.name} leaves the queue after {waitqueue.boottime() - started:.0f} s",
                verb="create",
                sandbox=ticket.name,
                session=self.session,
            )

    def _claim(
        self, request: Request, name: str, ticket: waitqueue.Ticket | None
    ) -> tuple[str | None, int]:
        """Refuse a taken name; return what keeps the request out and the count queued ahead."""
        # Each attempt reconnects, since a waiter may outlast a daemon restart.
        backend = self.backend(require_slice=True)
        if self.paths.sandbox(name).exists() or any(
            info.name == DOMAIN_PREFIX + name for info in backend.domains()
        ):
            msg = f"a sandbox named '{name}' exists"
            raise SbxError(msg, code="exists")
        ahead = len(self._ahead(ticket))
        problem = self._capacity_problem(request)
        if problem is None and ahead:
            problem = "earlier creates queue for capacity"
        return problem, ahead

    @contextlib.contextmanager
    def _admitted(self, request: Request, name: str) -> Generator[Backend]:
        """Hold the lock once `name` is free and the request fits the running and memory ceilings.

        With `request.wait`, a request that does not fit queues behind earlier
        waiters and proceeds only at the head of the queue, so a large request
        is never overtaken. A request without a wait never jumps the queue.
        """
        started = waitqueue.boottime()
        deadline = started + (request.wait or 0)
        ticket: waitqueue.Ticket | None = None
        try:
            while True:
                if self.cancelled():
                    msg = f"the create of '{name}' was cancelled while it waited"
                    raise SbxError(msg, code="cancelled")
                # Waiters behind the head skip the lock and the daemon.
                if ticket is None or not self._ahead(ticket):
                    with self.locked():
                        problem, ahead = self._claim(request, name, ticket)
                        # A waiter woken past its deadline, as after host sleep, never starts.
                        if problem is None and (ticket is None or waitqueue.boottime() < deadline):
                            self._dequeue(ticket, started)
                            yield self.backend()
                            return
                        if request.wait is None:
                            raise self._capacity_error(
                                cast("str", problem), ahead, code="over-limit"
                            )
                        ticket = ticket or self._enqueue(
                            request, name, cast("str", problem), ahead + 1, deadline
                        )
                remaining = deadline - waitqueue.boottime()
                if remaining <= 0:
                    raise self._wait_timeout(request, name, ticket)
                time.sleep(min(WAIT_POLL, remaining))
        finally:
            self._dequeue(ticket, None)

    def _wait_timeout(
        self, request: Request, name: str, ticket: waitqueue.Ticket | None
    ) -> SbxError:
        problem = self._capacity_problem(request)
        message = f"'{name}' waited {request.wait:g} s for capacity"
        if problem is not None:
            message += f": {problem}"
        return self._capacity_error(message, len(self._ahead(ticket)), code="wait-timeout")

    # Bases

    def base_image(self, base: str) -> Path:
        """Return the qcow2 image of a built, prepared, or exported base."""
        if (windows_settings := self.windows_base(base)) is not None:
            return windows.newest(windows_settings, base) / windows.DISK
        if base in self.settings.cloud_images:
            disk = self.paths.bases / base / cloud.DISK
            if not disk.is_file():
                msg = (
                    f"cloud base '{base}' is not prepared; the owner runs `sbx base prepare {base}`"
                )
                raise SbxError(msg, code="base-missing")
            return disk
        link = self.paths.bases / base
        if not link.exists():
            msg = f"base '{base}' is not built; run `sbx base build {base}`"
            raise SbxError(msg, code="base-missing")
        images = sorted(link.resolve(strict=True).glob("*.qcow2"))
        if len(images) != 1:
            msg = f"{link} holds {len(images)} qcow2 images, expected one"
            raise SbxError(msg, code="base-invalid")
        return images[0]

    def base_list(self) -> list[dict[str, object]]:
        """Report each Nix base's store path and each cloud base's prepared disk."""
        result: list[dict[str, object]] = []
        for flavour in FLAVOURS:
            link = self.paths.bases / flavour
            path = str(link.resolve()) if link.exists() else None
            result.append({"base": flavour, "kind": "nix", "built": path is not None, "path": path})
        for image, pinned in self.settings.cloud_images.items():
            disk = self.paths.bases / image / cloud.DISK
            path = str(disk) if disk.is_file() else None
            result.append(
                {
                    "base": image,
                    "kind": "cloud",
                    "built": path is not None,
                    "path": path,
                    "url": pinned.url,
                }
            )
        if self.settings.windows is not None:
            for base, directory in self.settings.windows.bases.items():
                found = windows.versions(directory)
                result.append(
                    {
                        "base": base,
                        "kind": "windows",
                        "built": bool(found),
                        "path": str(found[-1]) if found else None,
                        "versions": [version.name for version in found],
                    }
                )
        return result

    def base_build(self, flavour: str) -> dict[str, object]:
        """Build a Nix base from the configured flake; its out-link is the GC root."""
        if (windows_settings := self.windows_base(flavour)) is not None:
            msg = (
                f"Windows base '{flavour}' is exported from its guest's golden copy, not built; "
                f"the owner runs `systemctl start {windows_settings.unit(flavour)}`"
            )
            raise SbxError(msg, code="base-export")
        if flavour in self.settings.cloud_images:
            msg = (
                f"cloud base '{flavour}' comes from `sbx base prepare {flavour}`, run by the owner"
            )
            raise SbxError(msg, code="base-cloud")
        if flavour not in FLAVOURS:
            msg = f"unknown base '{flavour}'; bases: {', '.join(FLAVOURS)}"
            raise SbxError(msg, code="unknown-base")
        self.check_disk()
        self.paths.bases.mkdir(mode=0o700, parents=True, exist_ok=True)
        link = self.paths.bases / flavour
        installable = f"{self.settings.flake}#legacyPackages.x86_64-linux.workloads.sbx-{flavour}"
        journal.record(f"building base {flavour} from {installable}", verb="base-build")
        # Build logs go to stderr, which keeps --json output parseable.
        result = subprocess.run(
            [self.settings.tools.nix, "build", "--out-link", str(link), installable],
            stdout=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode != 0:
            msg = f"nix build {installable} exited {result.returncode}"
            raise SbxError(msg, code="build-failed")
        return {"base": flavour, "path": str(link.resolve())}

    def base_prepare(self, image: str) -> dict[str, object]:
        """Boot a pinned cloud image once with egress and keep its provisioned disk as a base."""
        if self.session is not None:
            msg = (
                "`sbx base prepare` boots an internet image with egress, "
                "so the owner runs it outside agent sessions"
            )
            raise SbxError(msg, code="owner-only")
        pinned = self.settings.cloud_images.get(image)
        if pinned is None:
            known = ", ".join(self.settings.cloud_images)
            msg = f"unknown cloud base '{image}'; cloud bases: {known}"
            raise SbxError(msg, code="unknown-base")
        name = cloud.PREPARE_PREFIX + image
        self._check_name(name)
        self.check_disk()
        self._check_egress()
        with self.locked():
            self._check_unused(image, name)
        journal.record(f"preparing base {image} from {pinned.url}", verb="base-prepare", base=image)
        fetched = run(
            [
                self.settings.tools.nix,
                "store",
                "prefetch-file",
                "--json",
                "--expected-hash",
                pinned.hash,
                pinned.url,
            ]
        )
        source = Path(json.loads(fetched)["storePath"])
        self._check_image(source)
        settings = self.settings
        request = Request(
            image, name, "egress", settings.default_memory_mib, settings.default_cpus, PREPARE_TTL
        )
        token = secrets.token_hex(8)
        # A failed start discards its own sandbox; a name another prepare holds stays.
        self._start(request, name, source, token, root=source, agent=False)
        try:
            result = self.exec_capture(
                name,
                ["sh", "-c", cloud.PREPARE_SCRIPT],
                timeout=PREPARE_TIMEOUT,
                agent=False,
                token=token,
            )
            if result.exit_code != 0:
                detail = result.stderr.decode(errors="replace").strip()[-2000:]
                status = "timed out" if result.timed_out else f"exited {result.exit_code}"
                msg = f"provisioning {image} {status}: {detail}"
                raise SbxError(msg, code="prepare-failed")
            # Unlocked, so sleep and other verbs proceed during the shutdown and the flatten.
            self._wait_shutoff(name, token)
            disk = self._publish_base(image, name, token)
        finally:
            with self.locked():
                self._discard(name, token)
        journal.record(f"prepared base {image}", verb="base-prepare", base=image)
        return {"base": image, "path": str(disk), "url": pinned.url, "hash": pinned.hash}

    def _check_image(self, path: Path) -> None:
        """Refuse an image whose header makes QEMU open another host file."""
        # The pinned hash only proves the file is the one first trusted.
        # A forced format makes qemu-img fail on anything but qcow2.
        command = [self.settings.tools.qemu_img, "info", "--output=json", "-f", "qcow2", str(path)]
        try:
            info = json.loads(run(command))
        except SbxError as error:
            msg = f"{path} is not a readable qcow2 image: {error}"
            raise SbxError(msg, code="image-unsafe") from error
        problems: list[str] = []
        if backing := info.get("backing-filename"):
            problems.append(f"backing file {backing!r}")
        if data := info.get("format-specific", {}).get("data", {}).get("data-file"):
            problems.append(f"data file {data!r}")
        if problems:
            msg = f"{path} names {', '.join(problems)}; sbx boots only self-contained qcow2 images"
            raise SbxError(msg, code="image-unsafe")

    def _check_unused(self, image: str, prepare: str) -> None:
        users = [
            sandbox.name
            for sandbox in self.owned()
            if sandbox.meta.base == image and sandbox.name != prepare
        ]
        if users:
            msg = f"sandboxes {', '.join(users)} run on base {image}; destroy them first"
            raise SbxError(msg, code="base-in-use")

    def _wait_shutoff(self, name: str, token: str) -> None:
        deadline = time.monotonic() + SHUTDOWN_TIMEOUT
        while self.created(name, token).domain.active:
            if time.monotonic() > deadline:
                msg = f"'{name}' did not power off within {SHUTDOWN_TIMEOUT}s"
                raise SbxError(msg, code="prepare-failed")
            time.sleep(1)

    def _publish_base(self, image: str, name: str, token: str) -> Path:
        """Flatten the shut-off prepare boot's disk into the base, replacing an older one."""
        bases = self.paths.bases
        bases.mkdir(mode=0o700, parents=True, exist_ok=True)
        staged = bases / f".{image}-{secrets.token_hex(4)}"
        staged.mkdir(mode=0o700)
        overlay = staged / "overlay.qcow2"
        target = bases / image
        try:
            # gc takes shut-off sandboxes, so the disk leaves the run directory under the lock.
            with self.locked():
                self.created(name, token)
                (self.paths.sandbox(name) / "disk.qcow2").rename(overlay)
            flat = staged / cloud.DISK
            run(
                [
                    self.settings.tools.qemu_img,
                    "convert",
                    "-q",
                    "-O",
                    "qcow2",
                    str(overlay),
                    str(flat),
                ]
            )
            overlay.unlink()
            flat.chmod(0o400)
            with self.locked():
                self._check_unused(image, name)
                if target.exists():
                    old = bases / f".{image}-{secrets.token_hex(4)}"
                    target.rename(old)
                    shutil.rmtree(old)
                staged.rename(target)
        finally:
            if staged.exists():
                shutil.rmtree(staged)
        return target / cloud.DISK

    # Lifecycle

    def _domain_xml(  # noqa: PLR0913, PLR0915, PLR0917
        self,
        name: str,
        directory: Path,
        meta: Meta,
        request: Request,
        authorized_key: str,
        nic: tuple[Egress, str] | None,
    ) -> str:
        domain = ET.Element("domain", type="kvm")

        def sub(parent: ET.Element, tag: str, text: str | None = None, **attrs: str) -> ET.Element:
            element = ET.SubElement(parent, tag, attrs)
            element.text = text
            return element

        cpuset = self.settings.cpuset
        sub(domain, "name", DOMAIN_PREFIX + name)
        sub(domain, "metadata").append(meta.element())
        sub(domain, "memory", str(request.memory_mib), unit="MiB")
        # virtiofs, which `sbx share attach` hot-plugs, needs shared guest memory.
        backing = sub(domain, "memoryBacking")
        sub(backing, "source", type="memfd")
        sub(backing, "access", mode="shared")
        # The user manager has no cpuset controller, so pinning goes through affinity.
        sub(domain, "vcpu", str(request.cpus), placement="static", cpuset=cpuset)
        sub(sub(domain, "cputune"), "emulatorpin", cpuset=cpuset)
        system = sub(domain, "os", firmware="efi")
        sub(system, "type", "hvm", arch="x86_64", machine="q35")
        firmware = sub(system, "firmware")
        sub(firmware, "feature", enabled="no", name="secure-boot")
        sub(system, "nvram", str(directory / "VARS.fd"))
        sub(system, "boot", dev="hd")
        seeded = request.base in self.settings.cloud_images
        if not seeded:
            sysinfo = sub(domain, "sysinfo", type="fwcfg")
            sub(sysinfo, "entry", authorized_key, name=CREDENTIAL)
        features = sub(domain, "features")
        sub(features, "acpi")
        sub(features, "apic")
        sub(features, "vmport", state="off")
        cpu = sub(domain, "cpu", mode="host-passthrough", check="none")
        sub(cpu, "feature", policy="disable", name="vmx")
        sub(domain, "clock", offset="utc")
        sub(domain, "on_poweroff", "destroy")
        sub(domain, "on_reboot", "restart")
        sub(domain, "on_crash", "destroy")
        devices = sub(domain, "devices")
        sub(devices, "emulator", self.settings.tools.emulator)
        disk = sub(devices, "disk", type="file", device="disk")
        sub(disk, "driver", name="qemu", type="qcow2", cache="unsafe", discard="unmap")
        sub(disk, "source", file=str(directory / "disk.qcow2"))
        sub(disk, "target", dev="vda", bus="virtio")
        if seeded:
            seed = sub(devices, "disk", type="file", device="cdrom")
            sub(seed, "driver", name="qemu", type="raw")
            sub(seed, "source", file=str(directory / cloud.SEED))
            sub(seed, "target", dev="sda", bus="sata")
            sub(seed, "readonly")
        if nic is not None:
            egress, mac = nic
            devices.append(bridge_interface(egress.bridge, mac))
        sub(devices, "controller", type="usb", model="none")
        # Untrusted class: the guest agent channel only, never a vdagent channel.
        channel = sub(devices, "channel", type="unix")
        sub(channel, "source", mode="bind")
        sub(channel, "target", type="virtio", name="org.qemu.guest_agent.0")
        # The emulator rebinds it to QEMU's own local vsock namespace (sbx.emulator).
        vsock = sub(devices, "vsock", model="virtio")
        sub(vsock, "cid", auto="yes")
        serial = sub(devices, "serial", type="file")
        sub(serial, "source", path=str(directory / "console.log"))
        sub(serial, "target", port="0")
        # A display device without <graphics> gives screenshots and no console socket;
        # GUI bases add a SPICE socket for libvirt clients, still without clipboard or files.
        if request.base in GUI_BASES:
            graphics = sub(devices, "graphics", type="spice")
            sub(graphics, "listen", type="socket")
            sub(graphics, "image", compression="off")
            sub(graphics, "clipboard", copypaste="no")
            sub(graphics, "filetransfer", enable="no")
        video = sub(devices, "video")
        sub(video, "model", type="virtio", heads="1")
        rng = sub(devices, "rng", model="virtio")
        sub(rng, "backend", "/dev/urandom", model="random")
        sub(devices, "memballoon", model="virtio", freePageReporting="on")
        # libvirt keeps a hot-plug slot only in definitions without PCI controllers, and
        # cold devices take listed root ports first: one per device element covers them.
        ports = len(devices) + SHARE_SLOTS
        sub(devices, "controller", type="pci", index="0", model="pcie-root")
        for _ in range(ports):
            sub(devices, "controller", type="pci", model="pcie-root-port")
        return self._serialize(domain, directory, request.base)

    def _serialize(self, domain: ET.Element, directory: Path, base: str) -> str:
        """Render the domain, adapted first when `base` is a Windows base."""
        if (windows_settings := self.windows_base(base)) is not None:
            windows.adapt(domain, directory, windows_settings.firmware)
        return ET.tostring(domain, encoding="unicode")

    def _discard(self, name: str, token: str | None = None) -> None:
        """Remove a sandbox's domain, directory, and grants; the caller holds the lock.

        With a token, only a domain and directory that carry it go, so a later
        sandbox of the same name survives the cleanup of an earlier one.
        """
        sandbox = next((sandbox for sandbox in self.owned() if sandbox.name == name), None)
        removed = False
        address = None
        if sandbox is not None and (token is None or sandbox.meta.token == token):
            address = self.address(sandbox)
            self.backend().remove(DOMAIN_PREFIX + name)
            removed = True
        directory = self.paths.sandbox(name)
        try:
            if directory.is_dir() and (token is None or self._carries(directory, token)):
                removed = True
                _remove_run_directory(directory)
        finally:
            if removed:
                self._revoke_grants(name, address)

    @staticmethod
    def _carries(directory: Path, token: str) -> bool:
        try:
            return (directory / CREATION_FILE).read_text() == token
        except FileNotFoundError:
            return False

    @staticmethod
    def _revoke_grants(name: str, address: str | None) -> None:
        """The sandbox is gone either way; a grant the helper keeps is reported, not fatal."""
        try:
            revoke_grants(name, address)
        except SbxError as error:
            journal.record(f"grants of {name} stay live: {error}", code=error.code, sandbox=name)
            print(f"sbx: grants of {name} stay live: {error}", file=sys.stderr)

    def _sandbox_key(self, name: str, directory: Path) -> str:
        """Generate the sandbox's SSH key and return its public half."""
        key = directory / "id_ed25519"
        comment = DOMAIN_PREFIX + name
        run(
            [
                self.settings.tools.ssh_keygen,
                "-q",
                "-t",
                "ed25519",
                "-N",
                "",
                "-C",
                comment,
                "-f",
                str(key),
            ]
        )
        return key.with_suffix(".pub").read_text().strip()

    def create(self, request: Request, *, token: str | None = None) -> dict[str, object]:
        """Start a sandbox and wait until it accepts commands.

        The creation token, the caller's or a fresh one, marks the domain and
        run directory and comes back as `token`.
        """
        token = token or secrets.token_hex(8)
        self._validate(request)
        name = request.name or f"{request.base}-{secrets.token_hex(3)}"
        self._check_name(name)
        image = self.base_image(request.base)
        # Prepared cloud disks and Windows exports live outside the store.
        outside = request.base in self.settings.cloud_images or self.windows_base(request.base)
        root = None if outside else image.parent
        with _terminate_raises():
            return self._start(request, name, image, token, root=root, agent=True)

    def _start(  # noqa: PLR0913
        self,
        request: Request,
        name: str,
        image: Path,
        token: str,
        *,
        root: Path | None,
        agent: bool,
    ) -> dict[str, object]:
        """Boot `name` on an overlay of `image`, which `root` keeps alive, and wait for it."""
        directory = self.paths.sandbox(name)
        with self._admitted(request, name) as backend:
            windows_settings = self.windows_base(request.base)
            if windows_settings is not None:
                # gc prunes superseded exports under this lock, so pick the newest only here.
                image = windows.newest(windows_settings, request.base) / windows.DISK
            tools = self.settings.tools
            info = json.loads(run([tools.qemu_img, "info", "-U", "--output=json", str(image)]))
            size = max(int(info["virtual-size"]), self.settings.disk_gib * GIB)
            linux_size = size if windows_settings is None else self.settings.disk_gib * GIB
            active = [sandbox.meta.base for sandbox in self.owned() if sandbox.domain.active]
            # Every running overlay may still grow to its full virtual size, or a Windows
            # one, whose disk is larger, to the daemon's file size limit.
            self.check_disk(
                reserve=sum(
                    self.settings.file_bytes if self.windows_base(base) else linux_size
                    for base in [*active, request.base]
                )
            )
            nic = (self._check_egress(), random_mac()) if request.net == "egress" else None
            now = int(self._clock())
            meta = Meta(
                request.base,
                str(image),
                request.net,
                now,
                now + request.ttl,
                self.session,
                token,
            )
            directory.mkdir(mode=0o700)
            try:
                (directory / CREATION_FILE).write_text(token)
                (directory / "xfer").mkdir(mode=0o700)
                if windows_settings is None:
                    public = self._sandbox_key(name, directory)
                else:
                    public = ""
                    windows.prepare(image.parent, directory)
                if root is not None:
                    # A per-sandbox root keeps the base through a rebuild and a GC.
                    gc_root = str(directory / "base")
                    run([tools.nix_store, "--add-root", gc_root, "--realise", str(root)])
                disk = str(directory / "disk.qcow2")
                run(
                    [
                        tools.qemu_img,
                        "create",
                        "-q",
                        "-f",
                        "qcow2",
                        "-F",
                        "qcow2",
                        "-b",
                        str(image),
                        disk,
                        str(size),
                    ]
                )
                if request.base in self.settings.cloud_images:
                    seed_nic = None if nic is None else (nic[1], nic[0].mtu)
                    self._write_seed(name, directory, public, nic=seed_nic)
                backend.start(self._domain_xml(name, directory, meta, request, public, nic))
            except BaseException:
                self._discard(name, token)
                raise
        journal.record(
            f"created sandbox {name}",
            verb="create",
            sandbox=name,
            base=request.base,
            session=self.session,
        )
        try:
            self._wait_ready(name, token, agent=agent)
        except BaseException:
            with self.locked():
                self._discard(name, token)
            raise
        return self.describe(self.created(name, token))

    def _console_tail(self, name: str) -> str:
        path = self.paths.sandbox(name) / "console.log"
        try:
            lines = path.read_text(errors="replace").splitlines()
        except FileNotFoundError:
            return ""
        return "\n".join(lines[-15:])

    def _write_seed(
        self, name: str, directory: Path, public_key: str, *, nic: tuple[str, int] | None
    ) -> None:
        """Pack the NoCloud seed; a fresh instance id makes cloud-init run again."""
        instance = f"{DOMAIN_PREFIX}{name}-{secrets.token_hex(4)}"
        files = directory / "seed"
        files.mkdir(mode=0o700)
        for leaf, content in cloud.seed_files(instance, public_key, nic=nic).items():
            (files / leaf).write_text(content)
        run(
            [
                self.settings.tools.xorriso,
                "-as",
                "mkisofs",
                "-quiet",
                "-output",
                str(directory / cloud.SEED),
                "-volid",
                "cidata",
                "-joliet",
                "-rock",
                str(files),
            ]
        )
        shutil.rmtree(files)

    def _wait_ready(self, name: str, token: str, *, agent: bool) -> None:
        """Wait for qemu-ga, SSH on vsock, and an egress lease; without `agent`, SSH only."""
        # Monotonic, so a host sleep during the boot wait does not count against it.
        deadline = time.monotonic() + self.settings.boot_timeout
        domain = DOMAIN_PREFIX + name
        while agent:
            self.created(name, token)
            try:
                self.backend().agent(domain, {"execute": "guest-ping"}, 5)
                break
            except SbxError:
                if time.monotonic() > deadline:
                    tail = self._console_tail(name)
                    msg = f"the guest agent of '{name}' did not answer; console:\n{tail}"
                    raise SbxError(msg, code="boot-timeout") from None
                time.sleep(1)
        if self.agent_only(name, token=token):
            return
        while True:
            sandbox = self.created(name, token)
            result = capture(self._ssh(name, sandbox.domain, ["true"]), 4096, 30)
            if result.exit_code == 0:
                break
            if time.monotonic() > deadline:
                detail = result.stderr.decode(errors="replace").strip()
                msg = f"ssh over vsock to '{name}' failed: {detail}"
                raise SbxError(msg, code="boot-timeout")
            time.sleep(1)
        # The address check asks qemu-ga; a prepare boot's script waits for the network itself.
        if agent and sandbox.meta.net == "egress":
            self._wait_address(sandbox, deadline)

    def _wait_address(self, sandbox: Sandbox, deadline: float) -> None:
        name, mac = sandbox.name, sandbox.domain.mac
        while True:
            address = self.address(sandbox, strict=True)
            # dnsmasq records the lease before the guest's ARP probe ends and it configures it.
            if address is not None and mac is not None:
                command: dict[str, object] = {"execute": "guest-network-get-interfaces"}
                reply = self.backend().agent(sandbox.domain.name, command, 5)
                if guest_holds(reply, mac, address):
                    return
            if time.monotonic() > deadline:
                if address is None:
                    msg = f"'{name}' got no DHCP lease on its egress bridge; console:\n"
                else:
                    msg = f"'{name}' never configured its lease {address}; console:\n"
                raise SbxError(msg + self._console_tail(name), code="no-address")
            time.sleep(1)

    def destroy(self, name: str) -> list[str]:
        """Remove one sandbox."""
        self._check_name(name)
        with self.locked():
            known = any(sandbox.name == name for sandbox in self.owned())
            if not known and not self.paths.sandbox(name).is_dir():
                msg = f"no sandbox named '{name}'"
                raise SbxError(msg, code="not-found")
            self._discard(name)
        journal.record(f"destroyed sandbox {name}", verb="destroy", sandbox=name)
        return [name]

    def destroy_created(self, token: str) -> list[str]:
        """Remove the sandboxes whose metadata carries `token`."""
        if not self.has_state():
            return []
        with self.locked():
            removed = [sandbox.name for sandbox in self.owned() if sandbox.meta.token == token]
            for name in removed:
                self._discard(name, token)
        for name in removed:
            journal.record(f"destroyed sandbox {name}", verb="destroy", sandbox=name)
        return removed

    def _require_session(self, *, mine: bool) -> None:
        if mine and self.session is None:
            msg = "--mine needs CLAUDE_CODE_SESSION_ID or CODEX_THREAD_ID, or a Codex MCP call"
            raise SbxError(msg, code="no-session")

    def destroy_where(
        self, *, mine: bool, expired: bool, timeout: float | None = None
    ) -> list[str]:
        """Remove the caller's sandboxes or the expired ones; `timeout` bounds the lock wait."""
        self._require_session(mine=mine)
        if expired and not self.host_synced():
            msg = (
                "the host clock is not NTP-synchronized, so TTLs cannot be judged; destroy by name"
            )
            raise SbxError(msg, code="clock-unsynced")
        if not self.has_state():
            return []
        removed: list[str] = []
        now = self._clock()
        with self.locked(timeout):
            for sandbox in self.owned():
                meta = sandbox.meta
                if (mine and meta.session == self.session) or (expired and meta.expires <= now):
                    self._discard(sandbox.name)
                    removed.append(sandbox.name)
        for name in removed:
            journal.record(f"destroyed sandbox {name}", verb="destroy", sandbox=name)
        return removed

    def listing(self, *, mine: bool) -> list[dict[str, object]]:
        """Describe every sandbox, or the caller's, then the creates queued for capacity."""
        self._require_session(mine=mine)
        queued = [
            ticket.as_json(position)
            for position, ticket in enumerate(waitqueue.live(self.paths.queue), 1)
            if not mine or ticket.session == self.session
        ]
        if not self.has_state():
            return queued
        sandboxes = [
            self.describe(sandbox)
            for sandbox in self.owned()
            if not mine or sandbox.meta.session == self.session
        ]
        return sandboxes + queued

    def info(self, name: str) -> dict[str, object]:
        """Describe one sandbox with its files."""
        sandbox = self.find(name)
        result = self.describe(sandbox)
        result["console"] = str(self.paths.sandbox(name) / "console.log")
        result["image"] = sandbox.meta.image
        return result

    def host_synced(self) -> bool:
        """Return whether timedatectl reports the host clock NTP-synchronized."""
        show = [self.settings.tools.timedatectl, "show", "-p", "NTPSynchronized", "--value"]
        result = subprocess.run(show, capture_output=True, text=True, check=False)
        return result.stdout.strip() == "yes"

    def _gc_reason(self, sandbox: Sandbox, now: float, *, synced: bool) -> str | None:
        # An unsynced clock, such as the RTC's right after resume, may run hours ahead.
        if synced and sandbox.meta.expires <= now:
            return "expired"
        # A prepare guest powers itself off before its disk is published.
        preparing = sandbox.name.startswith(cloud.PREPARE_PREFIX)
        if not sandbox.domain.active and not sandbox.domain.managed_save and not preparing:
            return "shut off"
        if not self.paths.sandbox(sandbox.name).is_dir():
            return "run directory missing"
        return None

    def gc(self, *, dry_run: bool) -> list[dict[str, str]]:
        """Remove stopped, half-removed, and, on a synced clock, expired sandboxes; then exports."""
        has_state = self.has_state()
        if not has_state and self.settings.windows is None:
            return []
        with self.locked():
            # Without sandbox state, gc never starts the daemon.
            actions, kept = self._gc_sandboxes(dry_run=dry_run) if has_state else ([], [])
            pruned = self._prune_bases(kept, dry_run=dry_run)
        if not dry_run:
            for action in actions:
                journal.record(
                    f"gc removed sandbox {action['name']}: {action['reason']}",
                    verb="gc",
                    sandbox=action["name"],
                )
            for action in pruned:
                journal.record(f"gc removed base export {action['name']}", verb="gc")
        return actions + pruned

    def _gc_sandboxes(self, *, dry_run: bool) -> tuple[list[dict[str, str]], list[Sandbox]]:
        """Remove what gc removes under the held lock; return the actions and the survivors."""
        actions: list[dict[str, str]] = []
        kept: list[Sandbox] = []
        synced = self.host_synced()
        now = self._clock()
        owned = {sandbox.name: sandbox for sandbox in self.owned()}
        for sandbox in owned.values():
            reason = self._gc_reason(sandbox, now, synced=synced)
            if reason is None:
                kept.append(sandbox)
                continue
            actions.append({"name": sandbox.name, "reason": reason})
            if not dry_run:
                self._discard(sandbox.name)
        for directory in self.paths.sandbox_dirs():
            if directory.name in owned:
                continue
            actions.append({"name": directory.name, "reason": "no domain"})
            if not dry_run:
                self._discard(directory.name)
        return actions, kept

    def _prune_bases(self, kept: Sequence[Sandbox], *, dry_run: bool) -> list[dict[str, str]]:
        """Remove Windows base exports that are neither the newest nor under a sandbox."""
        settings = self.settings.windows
        if settings is None:
            return []
        used = {Path(sandbox.meta.image).parent for sandbox in kept}
        actions: list[dict[str, str]] = []
        for base, directory in settings.bases.items():
            for version in windows.versions(directory)[:-1]:
                if version in used:
                    continue
                actions.append({"name": f"{base}/{version.name}", "reason": "superseded export"})
                if not dry_run:
                    shutil.rmtree(version)
        return actions

    # Guest access

    def _ssh_options(self, name: str, domain: DomainInfo) -> list[str]:
        if domain.cid is None or domain.pid is None:
            msg = f"sandbox '{name}' has no vsock CID; is it running?"
            raise SbxError(msg, code="not-running")
        directory = self.paths.sandbox(name)
        tools = self.settings.tools
        # The guest's CID exists only in the namespace its QEMU runs in.
        proxy = (
            f"{tools.nsenter} --target {domain.pid} --user --net --preserve-credentials -- "
            f"{tools.socat} - VSOCK-CONNECT:{domain.cid}:22"
        )
        options = {
            "IdentitiesOnly": "yes",
            "IdentityAgent": "none",
            "BatchMode": "yes",
            "StrictHostKeyChecking": "accept-new",
            "UserKnownHostsFile": str(directory / "known_hosts"),
            "GlobalKnownHostsFile": "/dev/null",
            "HostKeyAlias": DOMAIN_PREFIX + name,
            "ProxyCommand": proxy,
            "ConnectTimeout": "10",
            "ControlMaster": "no",
            "ControlPath": "none",
            "LogLevel": "ERROR",
        }
        argv = ["-F", "/dev/null", "-i", str(directory / "id_ed25519")]
        for key, value in options.items():
            argv += ["-o", f"{key}={value}"]
        return argv

    def _ssh(self, name: str, domain: DomainInfo, command: Sequence[str]) -> list[str]:
        options = self._ssh_options(name, domain)
        return [self.settings.tools.ssh, *options, "-T", "root@sbx", "--", shlex.join(command)]

    def running(self, name: str) -> Sandbox:
        """Return a sandbox that runs within its TTL."""
        return self._running(name)

    def _running(self, name: str, token: str | None = None) -> Sandbox:
        sandbox = self.created(name, token)
        if sandbox.meta.expires <= self._clock():
            msg = f"sandbox '{name}' is past its TTL; `sbx gc` removes it"
            raise SbxError(msg, code="expired")
        if not sandbox.domain.active:
            msg = f"sandbox '{name}' is {sandbox.domain.state}"
            raise SbxError(msg, code="not-running")
        return sandbox

    def exec_capture(
        self,
        name: str,
        command: Sequence[str],
        *,
        timeout: float | None,
        agent: bool,
        token: str | None = None,
    ) -> ExecResult:
        """Run a command and capture its output; with `token`, only in that creation."""
        sandbox = self._running(name, token)
        journal.record(
            f"exec in {name}: {shlex.join(command)}",
            verb="exec",
            sandbox=name,
            session=self.session,
        )
        if self.windows_base(sandbox.meta.base) is not None:
            guest = windows.Guest(self.backend(), sandbox.domain.name)
            return guest.execute(command, timeout=timeout, limit=self.settings.output_limit)
        bounded = guest_command(command, timeout)
        if agent:
            result = self._agent_exec(sandbox.domain.name, bounded, _backstop(timeout))
        else:
            argv = self._ssh(name, sandbox.domain, bounded)
            result = capture(argv, self.settings.output_limit, _backstop(timeout))
        if timeout is not None and result.exit_code == TIMEOUT_EXIT:
            return dataclasses.replace(result, timed_out=True)
        return result

    def exec_attached(
        self, name: str, command: Sequence[str], *, timeout: float | None, token: str | None = None
    ) -> int | None:
        """Run a command with the caller's stdio; return its exit code, or None on timeout."""
        sandbox = self._running(name, token)
        if self.windows_base(sandbox.meta.base) is not None:
            msg = f"sandbox '{name}' runs Windows, which takes commands through qemu-ga only"
            raise SbxError(msg, code="agent-only")
        journal.record(
            f"exec in {name}: {shlex.join(command)}",
            verb="exec",
            sandbox=name,
            session=self.session,
        )
        argv = self._ssh(name, sandbox.domain, guest_command(command, timeout))
        try:
            code = subprocess.run(argv, timeout=_backstop(timeout), check=False).returncode
        except subprocess.TimeoutExpired:
            return None
        return None if timeout is not None and code == TIMEOUT_EXIT else code

    def _agent_exec(self, domain: str, command: Sequence[str], timeout: float | None) -> ExecResult:
        backend = self.backend()
        # qemu-ga's PATH omits the system profile, so a login shell resolves the command.
        arguments = {"path": "/bin/sh", "arg": ["-lc", 'exec "$@"', "sbx", *command]}
        started = backend.agent(
            domain,
            {"execute": "guest-exec", "arguments": {**arguments, "capture-output": True}},
            10,
        )
        pid = _agent_int(_agent_return(started), "pid")
        if pid is None:
            msg = "guest-exec returned no pid"
            raise _agent_error(msg)
        deadline = None if timeout is None else self._clock() + timeout
        while True:
            status = _agent_return(
                backend.agent(
                    domain, {"execute": "guest-exec-status", "arguments": {"pid": pid}}, 10
                )
            )
            if not isinstance(status.get("exited"), bool):
                msg = "exited is not a boolean"
                raise _agent_error(msg)
            if status["exited"]:
                break
            if deadline is not None and self._clock() > deadline:
                return ExecResult(None, b"", b"", truncated=False, timed_out=True)
            time.sleep(0.2)
        limit = self.settings.output_limit
        stdout = _agent_data(status, "out-data")
        stderr = _agent_data(status, "err-data")
        truncated = bool(status.get("out-truncated") or status.get("err-truncated"))
        truncated = truncated or len(stdout) > limit or len(stderr) > limit
        code = _agent_int(status, "exitcode")
        signal = _agent_int(status, "signal")
        if code is None and signal is not None:
            code = 128 + signal
        if code is None:
            msg = "guest-exec-status has neither exitcode nor signal"
            raise _agent_error(msg)
        return ExecResult(code, stdout[:limit], stderr[:limit], truncated, timed_out=False)

    def host_roots(self) -> list[Path]:
        """Return the host directories `cp` reads from and writes to."""
        roots = [Path.home() / "trees", *self.settings.copy_roots]
        if tmpdir := os.environ.get("TMPDIR"):
            roots.append(Path(tmpdir))
        if checkout := self.checkout():
            roots.append(checkout)
        return [root.resolve() for root in roots if root.is_dir()]

    def checkout(self) -> Path | None:
        """Return the caller's git checkout, unless it is $HOME or holds it."""
        environment = {
            key: value for key, value in os.environ.items() if not key.startswith("GIT_")
        }
        result = subprocess.run(
            [self.settings.tools.git, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
            env=environment,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        toplevel = Path(result.stdout.strip()).resolve()
        # core.worktree can point the toplevel at any directory, such as $HOME.
        if not (toplevel / ".git").exists():
            return None
        home = Path.home().resolve()
        if toplevel == home or toplevel in home.parents:
            return None
        return toplevel

    def _denied(self, path: Path, roots: Sequence[Path]) -> SbxError:
        msg = f"{path} is outside the copy roots: {', '.join(map(str, roots))}"
        return SbxError(msg, code="path-denied")

    def _source(self, path: Path) -> Path:
        roots = self.host_roots()
        resolved = path.resolve(strict=True)
        if not _within(resolved, roots):
            raise self._denied(path, roots)
        if resolved.is_dir():
            for parent, dirs, files in os.walk(resolved):
                for entry in [*dirs, *files]:
                    candidate = Path(parent) / entry
                    if not candidate.is_symlink():
                        continue
                    # scp follows links, and a linked directory may link further out.
                    if candidate.is_dir():
                        msg = f"{candidate} links to a directory; copy its target instead"
                        raise SbxError(msg, code="path-denied")
                    if not _within(candidate.resolve(), roots):
                        msg = f"{candidate} links outside the copy roots"
                        raise SbxError(msg, code="path-denied")
        return resolved

    def _destination(self, path: Path, leaf: str) -> Path:
        """Return a host target that does not exist yet, under the copy roots."""
        roots = self.host_roots()
        resolved = path.resolve()
        if resolved.is_dir():
            resolved /= leaf
        if not resolved.parent.is_dir() or not _within(resolved.parent, roots):
            raise self._denied(path, roots)
        if os.path.lexists(resolved):
            msg = f"{resolved} exists; copies out never overwrite"
            raise SbxError(msg, code="exists")
        return resolved

    def _remote(self, argument: str) -> tuple[str, str] | None:
        name = remote_name(argument)
        if name is None:
            return None
        path = argument.partition(":")[2]
        if not path:
            msg = f"'{argument}' names no path inside the sandbox"
            raise SbxError(msg, code="invalid-argument")
        return name, path

    def copy(
        self, source: str, destination: str | None, *, token: str | None = None
    ) -> dict[str, object]:
        """Copy between the host and a sandbox over scp on vsock; with `token`, that creation."""
        remote_source = self._remote(source)
        remote_destination = None if destination is None else self._remote(destination)
        if (remote_source is None) == (remote_destination is None):
            msg = "exactly one side of cp names a sandbox as <name>:<path>"
            raise SbxError(msg, code="invalid-argument")
        if remote_destination is not None:
            name, guest_path = remote_destination
            local = self._source(Path(source))
            sandbox = self._running(name, token)
            journal.record(
                f"cp {local} {name}:{guest_path}", verb="cp", sandbox=name, session=self.session
            )
            if self.windows_base(sandbox.meta.base) is not None:
                guest = windows.Guest(self.backend(), sandbox.domain.name)
                return {
                    "from": str(local),
                    "to": f"{name}:{windows.copy_in(guest, local, guest_path)}",
                }
            options = self._ssh_options(name, sandbox.domain)
            run(
                [
                    self.settings.tools.scp,
                    *options,
                    "-q",
                    "-r",
                    str(local),
                    f"root@sbx:{guest_path}",
                ]
            )
            return {"from": str(local), "to": f"{name}:{guest_path}"}
        if remote_source is None:
            msg = "cp needs a sandbox source"
            raise SbxError(msg, code="invalid-argument")
        name, guest_path = remote_source
        return self._copy_out(name, guest_path, destination, token)

    def _copy_out(
        self, name: str, guest_path: str, destination: str | None, token: str | None
    ) -> dict[str, object]:
        sandbox = self._running(name, token)
        on_windows = self.windows_base(sandbox.meta.base) is not None
        source = windows.guest_path(guest_path) if on_windows else PurePosixPath(guest_path)
        leaf = source.name
        if leaf in {"", ".", ".."}:
            msg = f"'{guest_path}' names no file or directory to copy out"
            raise SbxError(msg, code="invalid-argument")
        xfer = self.paths.sandbox(name) / "xfer"
        if destination is None:
            target = xfer / leaf
            if os.path.lexists(target):
                msg = f"{target} exists; copies out never overwrite"
                raise SbxError(msg, code="exists")
        else:
            target = self._destination(Path(destination), leaf)
        budget = self._copy_budget()
        journal.record(
            f"cp {name}:{guest_path} {target}", verb="cp", sandbox=name, session=self.session
        )
        stage = xfer / f".stage-{secrets.token_hex(4)}"
        stage.mkdir(mode=0o700)
        try:
            staged = stage / leaf
            if not staged.resolve().is_relative_to(stage.resolve()):
                msg = f"'{guest_path}' leaves the transfer directory"
                raise SbxError(msg, code="path-denied")
            if isinstance(source, PureWindowsPath):
                guest = windows.Guest(self.backend(), sandbox.domain.name)
                windows.copy_out(guest, source, stage, budget)
            else:
                options = self._ssh_options(name, sandbox.domain)
                argv = [self.settings.tools.scp, *options, "-q", "-r", f"root@sbx:{guest_path}"]
                self._bounded_transfer([*argv, str(staged)], stage, budget)
            _strip_exec_bits(staged)
            self.check_disk()
            publish(staged, target)
        finally:
            shutil.rmtree(stage, ignore_errors=True)
        return {"from": f"{name}:{guest_path}", "to": str(target)}

    def _copy_budget(self) -> int:
        """Return the bytes a copy out may write before it passes the cap or the floor."""
        self.paths.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        stats = os.statvfs(self.paths.root)
        free = stats.f_bavail * stats.f_frsize
        budget = min(
            self.settings.disk_cap_bytes - self._usage(), free - self.settings.min_free_bytes
        )
        if budget <= 0:
            msg = "no room for a copy out under the disk cap and the free-space floor"
            raise SbxError(msg, code="disk-full")
        return budget

    def _bounded_transfer(self, argv: Sequence[str], stage: Path, budget: int) -> None:
        """Run scp with each file capped by RLIMIT_FSIZE and the stage by a watchdog."""

        def limit() -> None:
            resource.setrlimit(resource.RLIMIT_FSIZE, (budget, budget))

        over = False
        with (
            tempfile.TemporaryFile() as errors,
            subprocess.Popen(
                argv,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=errors,
                preexec_fn=limit,  # noqa: PLW1509
            ) as process,
        ):
            while True:
                try:
                    process.wait(WATCH_INTERVAL)
                    break
                except subprocess.TimeoutExpired:
                    if _allocated(stage) > budget:
                        over = True
                        process.kill()
            errors.seek(0)
            detail = errors.read().decode(errors="replace").strip()
        if over or process.returncode == -signal.SIGXFSZ:
            msg = f"the copy passed its {budget >> 20}M budget under the disk cap and floor"
            raise SbxError(msg, code="disk-full")
        if process.returncode != 0:
            msg = f"scp exited {process.returncode}: {detail}"
            raise SbxError(msg, code="command-failed")

    def screenshot(self, name: str, *, ocr: bool) -> dict[str, object]:
        """Save the display under the sandbox's xfer directory, optionally with OCR text."""
        sandbox = self._running(name)
        stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S")
        partial = self.paths.sandbox(name) / "xfer" / f".screenshot-{stamp}"
        mime = self.backend().screenshot(sandbox.domain.name, partial)
        extension = "png" if mime == "image/png" else "ppm"
        path = partial.with_name(f"screenshot-{stamp}.{extension}")
        partial.replace(path)
        journal.record(f"screenshot of {name}", verb="screenshot", sandbox=name)
        result: dict[str, object] = {"path": str(path), "mime": mime}
        if ocr:
            result["text"] = run([self.settings.tools.tesseract, str(path), "stdout"])
        return result

    def _gui(self, name: str) -> Sandbox:
        sandbox = self._running(name)
        if sandbox.meta.base not in GUI_BASES:
            msg = (
                f"sandbox '{name}' runs base {sandbox.meta.base}, which takes no display input; "
                f"GUI bases: {', '.join(sorted(GUI_BASES))}"
            )
            raise SbxError(msg, code="no-display")
        return sandbox

    def _send(self, domain: str, chords: Sequence[Sequence[int]]) -> None:
        backend = self.backend()
        for codes in chords:
            backend.send_key(domain, codes, KEY_HOLD_MS)
            # QEMU queues each press and release behind a hold delay and drops input past
            # 1024 queued events, so each chord drains before the next.
            time.sleep(2 * len(codes) * KEY_HOLD_MS / 1000)

    def key(self, name: str, specs: Sequence[str]) -> dict[str, object]:
        """Press each chord, such as `ctrl+alt+t` or `enter`, in turn."""
        try:
            chords = [keys.chord(spec) for spec in specs]
        except ValueError as error:
            raise SbxError(str(error), code="invalid-argument") from error
        sandbox = self._gui(name)
        journal.record(
            f"key in {name}: {' '.join(specs)}", verb="key", sandbox=name, session=self.session
        )
        self._send(sandbox.domain.name, chords)
        return {"sandbox": name, "keys": list(specs)}

    def type_text(self, name: str, text: str) -> dict[str, object]:
        """Type text as US-layout key presses."""
        if len(text) > TYPE_LIMIT:
            msg = f"type takes at most {TYPE_LIMIT} characters, got {len(text)}; split the text"
            raise SbxError(msg, code="invalid-argument")
        try:
            chords = keys.text_chords(text)
        except ValueError as error:
            raise SbxError(str(error), code="invalid-argument") from error
        sandbox = self._gui(name)
        # The text may be a secret the guest asks for, so only its length is logged.
        journal.record(
            f"type in {name}: {len(text)} characters",
            verb="type",
            sandbox=name,
            session=self.session,
        )
        self._send(sandbox.domain.name, chords)
        return {"sandbox": name, "characters": len(text)}
