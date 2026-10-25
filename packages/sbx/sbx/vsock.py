# Copyright (c) 2026 Bad3r
"""Listeners for vsock grants, inside each sandbox's QEMU namespace.

A sandbox without a network reaches only the vsock sockets of its QEMU's own
`local` vsock namespace (sbx.emulator). For every live grant in the list
workload-grantd writes, this service creates the grant's listeners inside that
namespace and forwards each connection to the host service on loopback from
the host's network namespace, where the service itself listens. A grant's
listeners and connections close when it expires, when it leaves the list, and
when its QEMU exits; a restored sandbox gets fresh listeners in its new
namespace. Nothing else listens, so a host vsock listener stays unreachable.
"""

import contextlib
import ctypes
import errno
import functools
import itertools
import json
import os
import re
import select
import selectors
import socket
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, NoReturn, cast

from sbx import emulator, journal
from sbx.core import CREATION_FILE, DOMAIN_PREFIX, NAME_PATTERN, Paths, SbxError

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

# workload-grantd writes it (packages/workloads/workloads/vsock.py).
STATE = Path("/run/workloads/vsock-grants.json")
DESTINATION = "127.0.0.1"
TOKEN_PATTERN = re.compile(r"[0-9a-f]{16}")
# Placement retries while a live grant has no listener, such as during a restore.
RETRY = 1.0
CHUNK = 1 << 16
BACKLOG = 16
# Below SCM_MAX_FD, the most descriptors one message carries.
FD_BATCH = 200
CONTROL_TIMEOUT = 5
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


def _parse_entry(entry: dict[str, object]) -> Grant:
    source, token = str(entry["source"]), str(entry["token"])
    sandbox = source.removeprefix(DOMAIN_PREFIX)
    if source == sandbox or NAME_PATTERN.fullmatch(sandbox) is None:
        msg = f"'{source}' is no sandbox"
        raise ValueError(msg)
    if TOKEN_PATTERN.fullmatch(token) is None:
        msg = f"'{token}' is no creation token"
        raise ValueError(msg)
    ranges = cast("list[dict[str, int]]", entry["ports"])
    return Grant(
        str(entry["id"]),
        sandbox,
        token,
        str(entry["target"]),
        tuple(port for span in ranges for port in range(int(span["from"]), int(span["to"]) + 1)),
        float(cast("float", entry["deadline"])),
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
        message, fds, _, _ = socket.recv_fds(channel, REQUEST_LIMIT, FD_BATCH)
        received.extend(fds)
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
        destination: str = DESTINATION,
    ) -> None:
        """Register the control socket and the list's watch."""
        self.selector = selectors.DefaultSelector()
        self.state = state
        self.runtime = runtime
        self.paths = paths
        self.opener = opener
        self.clock = clock
        self.owner = owner
        self.destination = destination
        self.served: dict[str, Served] = {}
        self.emulators: dict[str, Emulator] = {}
        self.list_error: str | None = None
        self.retry_at = 0.0
        self.watch = Watch(state.parent)
        self.watch.arm()
        self.selector.register(self.watch.fd, selectors.EVENT_READ, self._changed)
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

    def _emulator(self, grant: Grant) -> Emulator | None:
        try:
            token = (self.paths.sandbox(grant.sandbox) / CREATION_FILE).read_text()
        except FileNotFoundError:
            token = None
        if token != grant.token:
            msg = f"sandbox {grant.sandbox} is not the creation the grant names"
            raise SbxError(msg, code="replaced")
        running = self.emulators.get(grant.sandbox)
        if running is None:
            running = open_emulator(self.runtime, grant.sandbox)
            if running is None:
                return None
            self.emulators[grant.sandbox] = running
            self.selector.register(
                running.pidfd, selectors.EVENT_READ, functools.partial(self._stopped, grant.sandbox)
            )
        return running

    def _listen(self, served: Served, listeners: list[socket.socket]) -> None:
        for listener in listeners:
            listener.settimeout(0.0)
            port = int(listener.getsockname()[1])
            accept = functools.partial(self._accept, served, port)
            self.selector.register(listener, selectors.EVENT_READ, accept)
        served.listeners = listeners

    def _accept(self, served: Served, port: int, listener: object, _mask: int) -> None:
        if self.served.get(served.grant.grant) is not served:
            return
        try:
            guest, _ = cast("socket.socket", listener).accept()
        except BlockingIOError:
            return
        guest.settimeout(0.0)
        upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        upstream.settimeout(0.0)
        failure = upstream.connect_ex((self.destination, port))
        if failure not in {0, errno.EINPROGRESS}:
            guest.close()
            upstream.close()
            return
        served.pipes.add(Pipe(self.selector, guest, upstream, served.pipes.discard))

    def _shut(self, served: Served) -> None:
        """Close a grant's listeners and every connection they accepted."""
        for listener in served.listeners:
            self.selector.unregister(listener)
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
        running = self.emulators.pop(sandbox)
        self.selector.unregister(running.pidfd)
        os.close(running.pidfd)

    def _stopped(self, sandbox: str, _pidfd: object, _mask: int) -> None:
        """QEMU exited: its namespace goes with it, and so do the grant's listeners."""
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

    def _control(self, control: object, _mask: int) -> None:
        """Answer one sync request after applying the list."""
        try:
            connection, _ = cast("socket.socket", control).accept()
        except BlockingIOError:
            return
        with connection:
            connection.settimeout(CONTROL_TIMEOUT)
            try:
                request = b""
                while len(request) <= REQUEST_LIMIT and (chunk := connection.recv(REQUEST_LIMIT)):
                    request += chunk
                verb = cast("dict[str, object]", json.loads(request)).get("verb")
                if verb != "sync":
                    connection.sendall(json.dumps({"failure": f"unknown verb {verb!r}"}).encode())
                    return
                self.reconcile()
                connection.sendall(json.dumps(self.status()).encode())
            except (OSError, ValueError, AttributeError) as error:
                journal.record(f"vsock control request failed: {error}", verb="vsock")

    def _timeout(self, now: float) -> float | None:
        waits = [served.grant.deadline - now for served in self.served.values()]
        if not self.watch.watching or any(not served.listeners for served in self.served.values()):
            waits.append(self.retry_at - now)
        return max(0.0, min(waits)) if waits else None

    def step(self, timeout: float | None) -> None:
        """Wait for one round of events, then close expired grants and retry placements."""
        for key, mask in self.selector.select(timeout):
            cast("Callback", key.data)(key.fileobj, mask)
        now = self.clock()
        for grant_id, served in list(self.served.items()):
            if served.grant.deadline <= now:
                self._close(grant_id, "expired")
        if now >= self.retry_at:
            self.retry_at = now + RETRY
            if not self.watch.watching:
                self.watch.arm()
                self.reconcile()
            elif any(not served.listeners for served in self.served.values()):
                self._place()

    def close(self) -> None:
        """Close every listener, connection, and descriptor the proxy holds."""
        for grant_id in list(self.served):
            self._close(grant_id, "the proxy stopped")
        for sandbox in list(self.emulators):
            self._forget(sandbox)
        self.selector.close()
        os.close(self.watch.fd)

    def run(self) -> NoReturn:
        """Serve until stopped; every listener and connection closes with the process."""
        self.reconcile()
        while True:
            self.step(self._timeout(self.clock()))


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
