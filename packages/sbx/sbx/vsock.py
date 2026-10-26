# Copyright (c) 2026 Bad3r
"""Listeners for vsock grants, inside each sandbox's QEMU namespace.

A sandbox without a network reaches only the vsock sockets of its QEMU's own
`local` vsock namespace (sbx.emulator). For every live grant in the list
workload-grantd writes, this service creates the grant's listeners inside that
namespace and forwards each connection to the host service from the host's
network namespace, where the service itself listens. A grant's
listeners and connections close when it expires, when it leaves the list, and
when its QEMU exits; a restored sandbox gets fresh listeners in its new
namespace. Nothing else listens, so a host vsock listener stays unreachable.
"""

import contextlib
import ctypes
import errno
import fcntl
import functools
import itertools
import json
import os
import re
import select
import selectors
import socket
import struct
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, NoReturn, cast

from sbx import emulator, journal
from sbx.errors import SbxError
from sbx.model import CREATION_FILE, DOMAIN_PREFIX, NAME_PATTERN

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

    from sbx.config import Paths

# workload-grantd writes it (packages/workloads/workloads/vsock.py).
STATE = Path("/run/workloads/vsock-grants.json")
LOOPBACK = "127.0.0.1"
BINDS = frozenset({"loopback", "any"})
TOKEN_PATTERN = re.compile(r"[0-9a-f]{16}")
# Placement retries while a live grant has no listener, such as during a restore.
RETRY = 1.0
CHUNK = 1 << 16
BACKLOG = 16
# Below SCM_MAX_FD, the most descriptors one message carries.
FD_BATCH = 200
CONTROL_TIMEOUT = 5
# Connections one grant, and one sandbox's grants together, hold before accepting pauses.
GRANT_CONNECTIONS = 64
SANDBOX_CONNECTIONS = 256
# Errors after which accepting pauses for RETRY instead of spinning on a full table.
RESOURCE_ERRORS = frozenset({errno.EMFILE, errno.ENFILE, errno.ENOBUFS, errno.ENOMEM})
SIOCGIFFLAGS = 0x8913
SIOCGIFADDR = 0x8915
IFF_UP = 0x1
IFF_LOOPBACK = 0x8
SYS_NET = Path("/sys/class/net")
REQUEST_LIMIT = 4096
SD_LISTEN_FDS_START = 3
IN_CLOSE_WRITE = 0x8
IN_MOVED_TO = 0x80
IN_CREATE = 0x100
IN_DELETE = 0x200
IN_NONBLOCK = 0o4000
IN_CLOEXEC = 0o2000000
WATCH_MASK = IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE

# Callbacks the event loop runs with the ready object and its event mask.
type Callback = Callable[[object, int], None]
# Opens listeners on the ports inside the namespaces of the process a pidfd names.
type Opener = Callable[[int, Sequence[int]], list[socket.socket]]


def boottime() -> float:
    """The clock workload-grantd writes deadlines in."""
    return time.clock_gettime(time.CLOCK_BOOTTIME)


@dataclass(frozen=True)
class Grant:
    """One live entry of the list: a sandbox creation, its ports, and its deadline."""

    grant: str
    sandbox: str
    token: str
    target: str
    ports: tuple[int, ...]
    deadline: float
    # The service's `bind`: `loopback` or `any`.
    bind: str


def _parse_entry(entry: dict[str, object]) -> Grant:
    source, token = str(entry["source"]), str(entry["token"])
    sandbox = source.removeprefix(DOMAIN_PREFIX)
    if source == sandbox or NAME_PATTERN.fullmatch(sandbox) is None:
        msg = f"'{source}' is no sandbox"
        raise ValueError(msg)
    if TOKEN_PATTERN.fullmatch(token) is None:
        msg = f"'{token}' is no creation token"
        raise ValueError(msg)
    bind = str(entry["bind"])
    if bind not in BINDS:
        msg = f"'{bind}' is no bind mode"
        raise ValueError(msg)
    ranges = cast("list[dict[str, int]]", entry["ports"])
    return Grant(
        str(entry["id"]),
        sandbox,
        token,
        str(entry["target"]),
        tuple(port for span in ranges for port in range(int(span["from"]), int(span["to"]) + 1)),
        float(cast("float", entry["deadline"])),
        bind,
    )


def parse_grants(text: str) -> list[Grant]:
    """Read the list workload-grantd writes."""
    try:
        listing = cast("dict[str, object]", json.loads(text))
        return [_parse_entry(entry) for entry in cast("list[dict[str, object]]", listing["grants"])]
    except (AttributeError, KeyError, TypeError, ValueError) as error:
        msg = f"the vsock grant list is malformed: {error}"
        raise SbxError(msg, code="vsock-list") from error


def read_grants(path: Path, owner: int = 0) -> list[Grant]:
    """Read the list, which only its owner, root, may write; a missing list holds nothing."""
    try:
        with path.open() as handle:
            info = os.fstat(handle.fileno())
            text = handle.read()
    except FileNotFoundError:
        return []
    if info.st_uid != owner or info.st_mode & 0o022:
        msg = f"{path} is writable by someone other than uid {owner}"
        raise SbxError(msg, code="vsock-list")
    return parse_grants(text)


@dataclass(frozen=True)
class Emulator:
    """A running QEMU, pinned by a pidfd so its pid cannot be reused under it."""

    pid: int
    pidfd: int


def _exited(pidfd: int) -> bool:
    poller = select.poll()
    poller.register(pidfd, select.POLLIN)
    return bool(poller.poll(0))


def open_emulator(runtime: Path, sandbox: str) -> Emulator | None:
    """The sandbox's running QEMU from libvirt's pid file, or None when it runs none."""
    domain = DOMAIN_PREFIX + sandbox
    try:
        pid = int((runtime / "libvirt" / "qemu" / "run" / f"{domain}.pid").read_text())
        pidfd = os.pidfd_open(pid)
    except FileNotFoundError, ProcessLookupError:
        return None
    except ValueError as error:
        msg = f"the pid file of {domain} holds no pid"
        raise SbxError(msg, code="vsock-place") from error
    try:
        arguments = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    except OSError:
        arguments = []
    name = f"guest={domain}".encode()
    # Checked after the read, so a live pidfd proves the arguments were its process's.
    # libvirt writes the pid file before its child execs the emulator.
    if _exited(pidfd) or not any(arg == name or arg.startswith(name + b",") for arg in arguments):
        os.close(pidfd)
        return None
    return Emulator(pid, pidfd)


def _netns() -> tuple[int, int]:
    info = Path("/proc/self/ns/net").stat()
    return info.st_dev, info.st_ino


def _bind_in(pidfd: int, ports: Sequence[int]) -> list[socket.socket]:
    """Join the emulator's namespaces, then listen there; the caller is a forked child."""
    host = _netns()
    os.setns(pidfd, os.CLONE_NEWUSER | os.CLONE_NEWNET)
    if _netns() == host:
        msg = "the emulator runs in the host's network namespace"
        raise SbxError(msg, code="vsock-place")
    # A global namespace would let every guest in it reach the listener.
    emulator.check_local(emulator.NS_MODE)
    listeners: list[socket.socket] = []
    for port in ports:
        listener = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        listener.bind((socket.VMADDR_CID_ANY, port))
        listener.listen(BACKLOG)
        listeners.append(listener)
    return listeners


def _listen_in(channel: socket.socket, pidfd: int, ports: Sequence[int]) -> NoReturn:
    """Send the listeners, or why there are none, back to the parent; never returns."""
    code = 1
    try:
        listeners = _bind_in(pidfd, ports)
        for batch in itertools.batched(listeners, FD_BATCH, strict=False):
            socket.send_fds(channel, [b"fds"], [listener.fileno() for listener in batch])
        channel.send(b"ok")
        code = 0
    except BaseException as error:  # noqa: BLE001
        with contextlib.suppress(OSError):
            channel.send(f"error {error}".encode())
    finally:
        os._exit(code)


def _receive(channel: socket.socket, received: list[int]) -> None:
    while True:
        message, fds, flags, _ = socket.recv_fds(channel, REQUEST_LIMIT, FD_BATCH)
        received.extend(fds)
        if flags & socket.MSG_CTRUNC:
            msg = "the kernel dropped listener descriptors in transit"
            raise SbxError(msg, code="vsock-place")
        if message == b"ok":
            return
        if message != b"fds":
            detail = message.removeprefix(b"error ").decode(errors="replace")
            msg = detail or "the namespace helper exited without an answer"
            raise SbxError(msg, code="vsock-place")


def open_listeners(pidfd: int, ports: Sequence[int]) -> list[socket.socket]:
    """Create vsock listeners inside the namespaces of the process `pidfd` names.

    Joining a user namespace is one-way, so a forked child joins, listens, and
    passes the descriptors back. The sockets keep the namespace they were
    created in, so this process accepts on them from the host's namespace.
    """
    ours, theirs = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    child = os.fork()
    if child == 0:
        ours.close()
        _listen_in(theirs, pidfd, ports)
    theirs.close()
    received: list[int] = []
    try:
        _receive(ours, received)
    except BaseException:
        for fd in received:
            os.close(fd)
        raise
    finally:
        ours.close()
        os.waitpid(child, 0)
    return [socket.socket(fileno=fd) for fd in received]


def host_address() -> str | None:
    """The first IPv4 address, by interface index, of an interface that is up and not loopback."""
    # sysfs, not if_nameindex(), which needs the netlink family the unit does not allow.
    interfaces: list[tuple[int, str]] = []
    devices: list[Path] = []
    # Without sysfs, as in a build sandbox, no address is known and nothing connects.
    with contextlib.suppress(FileNotFoundError):
        devices = list(SYS_NET.iterdir())
    for device in devices:
        with contextlib.suppress(OSError, ValueError):
            interfaces.append((int((device / "ifindex").read_text()), device.name))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        for _, name in sorted(interfaces):
            request = struct.pack("256s", name.encode())
            try:
                flags = struct.unpack_from("H", fcntl.ioctl(probe, SIOCGIFFLAGS, request), 16)[0]
                if not flags & IFF_UP or flags & IFF_LOOPBACK:
                    continue
                address = fcntl.ioctl(probe, SIOCGIFADDR, request)[20:24]
            except OSError:
                # The interface has no IPv4 address, or it vanished since the listing.
                continue
            return socket.inet_ntoa(address)
    return None


def destination(bind: str) -> str | None:
    """Where a granted connection goes: loopback for a `loopback` service.

    A `bind = "any"` service gets a host address instead, so the grant never
    reaches a loopback-only listener in its range.
    """
    return LOOPBACK if bind == "loopback" else host_address()


class Pipe:
    """Copies bytes both ways between a guest connection and its upstream connection."""

    def __init__(
        self,
        selector: selectors.BaseSelector,
        guest: socket.socket,
        upstream: socket.socket,
        done: Callable[[Pipe], None],
    ) -> None:
        """Register both ends; the upstream connect is still in progress."""
        self.selector = selector
        self.ends = (guest, upstream)
        # Bytes waiting to be written to ends[i].
        self.pending = [b"", b""]
        # Whether ends[i] reached end of file.
        self.drained = [False, False]
        self.masks = [0, 0]
        self.connected = False
        self.closed = False
        self.done = done
        self._update()

    def handle(self, end: object, mask: int) -> None:
        """Move what the ready end allows, and close both ends on any socket error."""
        if self.closed:
            return
        index = self.ends.index(cast("socket.socket", end))
        try:
            if mask & selectors.EVENT_WRITE:
                self._writable(index)
            if mask & selectors.EVENT_READ:
                self._readable(index)
        except OSError:
            self.close()
            return
        if all(self.drained) and not any(self.pending):
            self.close()
            return
        self._update()

    def _writable(self, index: int) -> None:
        end = self.ends[index]
        if not self.connected:
            failure = end.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
            if failure:
                raise OSError(failure, os.strerror(failure))
            self.connected = True
            return
        sent = end.send(self.pending[index])
        self.pending[index] = self.pending[index][sent:]
        if not self.pending[index] and self.drained[1 - index]:
            end.shutdown(socket.SHUT_WR)

    def _readable(self, index: int) -> None:
        data = self.ends[index].recv(CHUNK)
        other = 1 - index
        if data:
            self.pending[other] += data
            return
        self.drained[index] = True
        if not self.pending[other]:
            self.ends[other].shutdown(socket.SHUT_WR)

    def _update(self) -> None:
        for index, end in enumerate(self.ends):
            mask = 0
            if self.connected and not self.drained[index] and not self.pending[1 - index]:
                mask |= selectors.EVENT_READ
            if self.pending[index] or (index == 1 and not self.connected):
                mask |= selectors.EVENT_WRITE
            if mask == self.masks[index]:
                continue
            if not self.masks[index]:
                self.selector.register(end, mask, self.handle)
            elif not mask:
                self.selector.unregister(end)
            else:
                self.selector.modify(end, mask, self.handle)
            self.masks[index] = mask

    def close(self) -> None:
        """Close both ends at once; the guest sees its connection end."""
        if self.closed:
            return
        self.closed = True
        for index, end in enumerate(self.ends):
            if self.masks[index]:
                self.selector.unregister(end)
            end.close()
        self.done(self)


@dataclass
class Served:
    """A live grant, its listeners, and the connections they accepted."""

    grant: Grant
    listeners: list[socket.socket] = field(default_factory=list[socket.socket])
    pipes: set[Pipe] = field(default_factory=set[Pipe])
    state: str = "waiting"
    error: str | None = None
    # Whether the listeners sit in the selector; they leave it at a connection cap.
    accepting: bool = False
    # Accepting pauses until then after the descriptor table filled.
    paused_until: float = 0.0
    accept_error: str | None = None


@dataclass
class Request:
    """One control connection, read and answered without blocking the loop."""

    connection: socket.socket
    deadline: float
    received: bytes = b""
    reply: bytes | None = None


class Watch:
    """inotify on the list's directory; without the directory, the proxy polls."""

    def __init__(self, directory: Path) -> None:
        """Open the inotify descriptor."""
        self.directory = directory
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.fd: int = self.libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
        if self.fd < 0:
            number = ctypes.get_errno()
            raise OSError(number, os.strerror(number))
        self.watching = False

    def arm(self) -> bool:
        """Watch the directory if it exists now; return whether it is watched."""
        if not self.watching:
            added: int = self.libc.inotify_add_watch(
                self.fd, os.fsencode(self.directory), WATCH_MASK
            )
            self.watching = added >= 0
        return self.watching

    def drain(self) -> None:
        """Discard the queued events; a vanished directory drops the watch."""
        with contextlib.suppress(BlockingIOError):
            while os.read(self.fd, CHUNK):
                pass
        if not self.directory.is_dir():
            self.watching = False


class Proxy:
    """The event loop that holds every grant's listeners and connections."""

    def __init__(  # noqa: PLR0913
        self,
        control: socket.socket | None,
        *,
        state: Path,
        runtime: Path,
        paths: Paths,
        opener: Opener = open_listeners,
        clock: Callable[[], float] = boottime,
        owner: int = 0,
        resolve: Callable[[str], str | None] = destination,
        grant_connections: int = GRANT_CONNECTIONS,
        sandbox_connections: int = SANDBOX_CONNECTIONS,
    ) -> None:
        """Register the control socket, the list's watch, and the deadline timer."""
        self.selector = selectors.DefaultSelector()
        self.state = state
        self.runtime = runtime
        self.paths = paths
        self.opener = opener
        self.clock = clock
        self.owner = owner
        self.resolve = resolve
        self.grant_connections = grant_connections
        self.sandbox_connections = sandbox_connections
        self.served: dict[str, Served] = {}
        self.emulators: dict[str, Emulator] = {}
        self.requests: dict[socket.socket, Request] = {}
        self.list_error: str | None = None
        self.retry_at = 0.0
        self.watch = Watch(state.parent)
        self.watch.arm()
        self.selector.register(self.watch.fd, selectors.EVENT_READ, self._changed)
        # A CLOCK_BOOTTIME timer keeps counting through host suspend, where select's
        # timeout stops, so deadlines fire on the clock workload-grantd writes them in.
        self.timer = os.timerfd_create(time.CLOCK_BOOTTIME, flags=os.TFD_NONBLOCK | os.TFD_CLOEXEC)
        self.selector.register(self.timer, selectors.EVENT_READ, self._ticked)
        if control is not None:
            control.settimeout(0.0)
            self.selector.register(control, selectors.EVENT_READ, self._control)

    # Grants

    def reconcile(self) -> None:
        """Serve exactly the live grants of the list; an unreadable list serves none."""
        try:
            grants = read_grants(self.state, self.owner)
            self.list_error = None
        except (SbxError, OSError) as error:
            grants = []
            if str(error) != self.list_error:
                journal.record(f"vsock grants closed: {error}", verb="vsock", code="vsock-list")
            self.list_error = str(error)
        now = self.clock()
        wanted = {grant.grant: grant for grant in grants if grant.deadline > now}
        for grant_id, served in list(self.served.items()):
            if wanted.get(grant_id) != served.grant:
                self._close(grant_id, "revoked")
        for grant_id, grant in wanted.items():
            self.served.setdefault(grant_id, Served(grant))
        self._place()

    def _place(self) -> None:
        """Give each unplaced grant its listeners, then drop emulators no grant needs."""
        for served in self.served.values():
            if served.listeners:
                continue
            grant = served.grant
            try:
                running = self._emulator(grant)
                if running is None:
                    state, error = "waiting", f"sandbox {grant.sandbox} is not running"
                else:
                    self._listen(served, self.opener(running.pidfd, grant.ports))
                    state, error = "listening", None
            except (SbxError, OSError) as failure:
                state, error = "failed", str(failure)
            if (state, error) != (served.state, served.error):
                journal.record(
                    f"vsock grant {grant.grant} of {grant.sandbox}: {error or state}",
                    verb="vsock",
                    sandbox=grant.sandbox,
                    grant=grant.grant,
                )
            served.state, served.error = state, error
        needed = {served.grant.sandbox for served in self.served.values()}
        for sandbox in set(self.emulators) - needed:
            self._forget(sandbox)
        self._balance()

    def _replaced(self, grant: Grant) -> bool:
        try:
            token = (self.paths.sandbox(grant.sandbox) / CREATION_FILE).read_text()
        except FileNotFoundError:
            token = None
        return token != grant.token

    def _emulator(self, grant: Grant) -> Emulator | None:
        msg = f"sandbox {grant.sandbox} is not the creation the grant names"
        if self._replaced(grant):
            raise SbxError(msg, code="replaced")
        running = self.emulators.get(grant.sandbox)
        if running is None:
            running = open_emulator(self.runtime, grant.sandbox)
            if running is None:
                return None
            # The sandbox may have been replaced while its emulator was looked up.
            if self._replaced(grant):
                os.close(running.pidfd)
                raise SbxError(msg, code="replaced")
            self.emulators[grant.sandbox] = running
            self.selector.register(
                running.pidfd,
                selectors.EVENT_READ,
                functools.partial(self._stopped, grant.sandbox, running),
            )
        return running

    def _listen(self, served: Served, listeners: list[socket.socket]) -> None:
        if len(listeners) != len(served.grant.ports):
            for listener in listeners:
                listener.close()
            msg = f"{len(listeners)} of {len(served.grant.ports)} listeners arrived"
            raise SbxError(msg, code="vsock-place")
        for listener in listeners:
            listener.settimeout(0.0)
        served.listeners = listeners
        served.accepting = False

    def _accepting(self, served: Served, *, accepting: bool) -> None:
        if served.accepting == accepting:
            return
        for listener in served.listeners:
            if accepting:
                port = int(listener.getsockname()[1])
                accept = functools.partial(self._accept, served, port)
                self.selector.register(listener, selectors.EVENT_READ, accept)
            else:
                self.selector.unregister(listener)
        served.accepting = accepting

    def _balance(self) -> None:
        """Accept on each grant only below its caps and outside a pause."""
        now = self.clock()
        held: dict[str, int] = {}
        for served in self.served.values():
            held[served.grant.sandbox] = held.get(served.grant.sandbox, 0) + len(served.pipes)
        for served in self.served.values():
            if served.listeners:
                self._accepting(
                    served,
                    accepting=len(served.pipes) < self.grant_connections
                    and held[served.grant.sandbox] < self.sandbox_connections
                    and now >= served.paused_until,
                )

    def _connect(
        self, listener: socket.socket, bind: str, port: int, opened: list[socket.socket]
    ) -> None:
        """Accept one guest connection and start its upstream connect, keeping both in `opened`."""
        guest, _ = listener.accept()
        opened.append(guest)
        address = self.resolve(bind)
        if address is None:
            raise OSError(errno.EADDRNOTAVAIL, "the host has no non-loopback IPv4 address")
        guest.settimeout(0.0)
        upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        opened.append(upstream)
        upstream.settimeout(0.0)
        failure = upstream.connect_ex((address, port))
        if failure not in {0, errno.EINPROGRESS}:
            raise OSError(failure, os.strerror(failure))

    def _accept(self, served: Served, port: int, listener: object, _mask: int) -> None:
        if self.served.get(served.grant.grant) is not served or listener not in served.listeners:
            return
        opened: list[socket.socket] = []
        try:
            self._connect(cast("socket.socket", listener), served.grant.bind, port, opened)
        except BlockingIOError:
            return
        except OSError as error:
            for end in opened:
                end.close()
            if error.errno in RESOURCE_ERRORS:
                served.paused_until = self.clock() + RETRY
            if str(error) != served.accept_error:
                journal.record(
                    f"vsock grant {served.grant.grant} refused a connection on {port}: {error}",
                    verb="vsock",
                    sandbox=served.grant.sandbox,
                    grant=served.grant.grant,
                )
            served.accept_error = str(error)
            self._balance()
            return
        served.accept_error = None
        guest, upstream = opened
        done = functools.partial(self._finished, served)
        served.pipes.add(Pipe(self.selector, guest, upstream, done))
        self._balance()

    def _finished(self, served: Served, pipe: Pipe) -> None:
        served.pipes.discard(pipe)
        self._balance()

    def _shut(self, served: Served) -> None:
        """Close a grant's listeners and every connection they accepted."""
        self._accepting(served, accepting=False)
        for listener in served.listeners:
            listener.close()
        served.listeners = []
        for pipe in list(served.pipes):
            pipe.close()

    def _close(self, grant_id: str, why: str) -> None:
        served = self.served.pop(grant_id)
        self._shut(served)
        journal.record(
            f"vsock grant {grant_id} of {served.grant.sandbox} closed: {why}",
            verb="vsock",
            sandbox=served.grant.sandbox,
            grant=grant_id,
        )

    def _forget(self, sandbox: str) -> None:
        running = self.emulators.pop(sandbox, None)
        if running is not None:
            self.selector.unregister(running.pidfd)
            os.close(running.pidfd)

    def _stopped(self, sandbox: str, running: Emulator, _pidfd: object, _mask: int) -> None:
        """QEMU exited: its namespace goes with it, and so do the grant's listeners."""
        if self.emulators.get(sandbox) is not running:
            return
        self._forget(sandbox)
        for served in self.served.values():
            if served.grant.sandbox == sandbox:
                self._shut(served)
                served.state, served.error = "waiting", f"sandbox {sandbox} stopped"
        self.retry_at = self.clock() + RETRY

    def status(self) -> dict[str, object]:
        """Each live grant's state."""
        return {
            "grants": {
                grant_id: {
                    "sandbox": served.grant.sandbox,
                    "target": served.grant.target,
                    "state": served.state,
                    "error": served.error,
                    "connections": len(served.pipes),
                }
                for grant_id, served in sorted(self.served.items())
            },
            "list_error": self.list_error,
        }

    # Event loop

    def _changed(self, _fd: object, _mask: int) -> None:
        self.watch.drain()
        self.reconcile()

    def _ticked(self, _fd: object, _mask: int) -> None:
        with contextlib.suppress(BlockingIOError):
            os.read(self.timer, 8)

    def _arm(self) -> None:
        """Set the timer to the earliest deadline, or disarm it."""
        deadlines = [served.grant.deadline for served in self.served.values()]
        if not deadlines:
            os.timerfd_settime(self.timer, initial=0)
            return
        # Relative to the injected clock, on CLOCK_BOOTTIME, so suspend still counts.
        os.timerfd_settime(self.timer, initial=max(min(deadlines) - self.clock(), 1e-6))

    def _control(self, control: object, _mask: int) -> None:
        try:
            connection, _ = cast("socket.socket", control).accept()
        except OSError:
            return
        connection.settimeout(0.0)
        request = Request(connection, time.monotonic() + CONTROL_TIMEOUT)
        self.requests[connection] = request
        self.selector.register(
            connection, selectors.EVENT_READ, functools.partial(self._request, request)
        )

    def _request(self, request: Request, _connection: object, mask: int) -> None:
        """Read one sync request to its end, apply the list, then write the answer."""
        connection = request.connection
        try:
            if mask & selectors.EVENT_READ:
                chunk = connection.recv(REQUEST_LIMIT)
                if chunk:
                    request.received += chunk
                    if len(request.received) > REQUEST_LIMIT:
                        self._drop(request)
                    return
                request.reply = json.dumps(self._answer(request.received)).encode()
                self.selector.modify(
                    connection, selectors.EVENT_WRITE, functools.partial(self._request, request)
                )
            if mask & selectors.EVENT_WRITE and request.reply is not None:
                request.reply = request.reply[connection.send(request.reply) :]
                if not request.reply:
                    self._drop(request)
        except BlockingIOError:
            return
        except OSError as error:
            journal.record(f"vsock control request failed: {error}", verb="vsock")
            self._drop(request)

    def _answer(self, raw: bytes) -> dict[str, object]:
        try:
            verb = cast("dict[str, object]", json.loads(raw)).get("verb")
        except (ValueError, AttributeError) as error:
            return {"failure": f"the request is no JSON object: {error}"}
        if verb != "sync":
            return {"failure": f"unknown verb {verb!r}"}
        self.reconcile()
        return self.status()

    def _drop(self, request: Request) -> None:
        if self.requests.pop(request.connection, None) is not None:
            self.selector.unregister(request.connection)
            request.connection.close()

    def timeout(self, now: float) -> float | None:
        """Retries and control deadlines only; grant deadlines fire through the timer."""
        waits = [request.deadline - time.monotonic() for request in self.requests.values()]
        if not self.watch.watching or any(not served.listeners for served in self.served.values()):
            waits.append(self.retry_at - now)
        waits += [s.paused_until - now for s in self.served.values() if s.paused_until > now]
        return max(0.0, min(waits)) if waits else None

    def step(self, timeout: float | None) -> None:
        """Wait for one round of events, then close expired grants and retry placements."""
        self._arm()
        for key, mask in self.selector.select(timeout):
            # An earlier callback this round may have closed or replaced this object.
            if self.selector.get_map().get(key.fd) is not key:
                continue
            cast("Callback", key.data)(key.fileobj, mask)
        now = self.clock()
        for grant_id, served in list(self.served.items()):
            if served.grant.deadline <= now:
                self._close(grant_id, "expired")
        for request in [r for r in self.requests.values() if r.deadline <= time.monotonic()]:
            self._drop(request)
        if now >= self.retry_at:
            self.retry_at = now + RETRY
            if not self.watch.watching:
                self.watch.arm()
                self.reconcile()
            elif any(not served.listeners for served in self.served.values()):
                self._place()
        self._balance()

    def close(self) -> None:
        """Close every listener, connection, and descriptor the proxy holds."""
        for grant_id in list(self.served):
            self._close(grant_id, "the proxy stopped")
        for sandbox in list(self.emulators):
            self._forget(sandbox)
        for request in list(self.requests.values()):
            self._drop(request)
        self.selector.close()
        os.close(self.watch.fd)
        os.close(self.timer)

    def run(self) -> NoReturn:
        """Serve until stopped; every listener and connection closes with the process."""
        self.reconcile()
        while True:
            self.step(self.timeout(self.clock()))


def runtime_dir() -> Path:
    """The caller's XDG runtime directory, where libvirt and the control socket live."""
    return Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")


def control_path() -> Path:
    """The control socket sbx-vsock.socket listens on."""
    return runtime_dir() / "sbx" / "vsock.sock"


def serve(paths: Paths) -> NoReturn:
    """Run as sbx-vsock.service, on the socket systemd passes."""
    if os.environ.get("LISTEN_PID") != str(os.getpid()) or os.environ.get("LISTEN_FDS") != "1":
        msg = "sbx vsock serve runs under sbx-vsock.socket, which passes its control socket"
        raise SbxError(msg, code="usage")
    control = socket.socket(fileno=SD_LISTEN_FDS_START)
    Proxy(control, state=STATE, runtime=runtime_dir(), paths=paths).run()


def sync(path: Path) -> dict[str, object]:
    """Have the proxy apply the list now; return each live grant's state."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(30)
        try:
            connection.connect(str(path))
        except (FileNotFoundError, ConnectionRefusedError) as error:
            msg = f"the vsock grant proxy is not reachable at {path}: {error}"
            raise SbxError(msg, code="vsock-proxy") from error
        connection.sendall(json.dumps({"verb": "sync"}).encode())
        connection.shutdown(socket.SHUT_WR)
        answer = b"".join(iter(lambda: connection.recv(CHUNK), b""))
    try:
        status = cast("dict[str, object]", json.loads(answer))
    except ValueError as error:
        msg = f"the vsock grant proxy answered no JSON: {error}"
        raise SbxError(msg, code="vsock-proxy") from error
    if "failure" in status:
        raise SbxError(str(status["failure"]), code="vsock-proxy")
    if status.get("list_error"):
        raise SbxError(str(status["list_error"]), code="vsock-list")
    return status
