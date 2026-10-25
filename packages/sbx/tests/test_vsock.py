# Copyright (c) 2026 Bad3r
"""The vsock grant proxy over TCP stand-ins for the in-namespace listeners."""

import json
import os
import resource
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock
from pathlib import Path
from typing import TYPE_CHECKING, cast

from sbx import vsock
from sbx.core import Paths, SbxError

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

# A sandbox creation token, not a credential.
TOKEN = "c" * 16
# Guests reach the stand-in listeners here; upstream services answer on 127.0.0.1.
GUEST_SIDE = "127.0.0.2"


class Echo(socketserver.StreamRequestHandler):
    """Echo each line back."""

    def handle(self) -> None:
        """Copy until the client closes."""
        for line in self.rfile:
            self.wfile.write(line)
            self.wfile.flush()


def entry(grant: str, port: int, deadline: float, **fields: object) -> dict[str, object]:
    """One list entry for sandbox `a`."""
    record: dict[str, object] = {
        "id": grant,
        "source": "sbx-a",
        "token": TOKEN,
        "target": f"host:dev:{port}",
        "ports": [{"from": port, "to": port}],
        "deadline": deadline,
        "bind": "loopback",
    }
    return record | fields


class ParseTest(unittest.TestCase):
    """Only a well-formed list owned by root alone is read."""

    def test_parse(self) -> None:
        """Ranges expand to ports; foreign sources and tokens are refused."""
        listed = {"grants": [entry("00000001", 80, 9.0) | {"ports": [{"from": 80, "to": 82}]}]}
        (grant,) = vsock.parse_grants(json.dumps(listed))
        self.assertEqual((grant.sandbox, grant.ports, grant.deadline), ("a", (80, 81, 82), 9.0))
        for bad in (
            entry("00000001", 80, 9.0, source="guest:dev"),
            entry("00000001", 80, 9.0, token="x"),  # noqa: S106
            entry("00000001", 80, 9.0, bind="lan"),
            {"id": "00000001"},
        ):
            with self.subTest(bad=bad), self.assertRaises(SbxError) as caught:
                vsock.parse_grants(json.dumps({"grants": [bad]}))
            self.assertEqual(caught.exception.code, "vsock-list")

    def test_owner(self) -> None:
        """A missing list holds nothing; another owner or a group-writable mode is refused."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "vsock-grants.json"
            self.assertEqual(vsock.read_grants(path, os.getuid()), [])
            path.write_text(json.dumps({"grants": []}))
            path.chmod(0o644)
            self.assertEqual(vsock.read_grants(path, os.getuid()), [])
            with self.assertRaises(SbxError):
                vsock.read_grants(path, os.getuid() + 1)
            path.chmod(0o664)
            with self.assertRaises(SbxError):
                vsock.read_grants(path, os.getuid())


class Fixture(unittest.TestCase):
    """A proxy over a scratch list, run directory, and libvirt runtime directory."""

    def setUp(self) -> None:
        """Lay out sandbox `a`, a stand-in QEMU for it, and two echo services."""
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        self.state = root / "run" / "workloads" / "vsock-grants.json"
        self.state.parent.mkdir(parents=True)
        self.runtime = root / "runtime"
        (self.runtime / "libvirt" / "qemu" / "run").mkdir(parents=True)
        self.paths = Paths(root / "share" / "sbx", root / "config")
        self.paths.sandbox("a").mkdir(parents=True)
        (self.paths.sandbox("a") / "creation").write_text(TOKEN)
        self.now = 1000.0
        self.opened: list[Sequence[int]] = []
        self.ports = [self.service(), self.service()]
        self.qemu = self.start_qemu()
        self.proxy = self.proxy_with()

    def proxy_with(
        self,
        control: socket.socket | None = None,
        *,
        clock: Callable[[], float] | None = None,
        resolve: Callable[[str], str | None] = vsock.destination,
        grant_connections: int = vsock.GRANT_CONNECTIONS,
        sandbox_connections: int = vsock.SANDBOX_CONNECTIONS,
    ) -> vsock.Proxy:
        """A proxy over the fixture, on the fake clock unless `clock` is given."""
        proxy = vsock.Proxy(
            control,
            state=self.state,
            runtime=self.runtime,
            paths=self.paths,
            opener=self.opener,
            clock=clock or (lambda: self.now),
            owner=os.getuid(),
            resolve=resolve,
            grant_connections=grant_connections,
            sandbox_connections=sandbox_connections,
        )
        self.addCleanup(proxy.close)
        return proxy

    def service(self) -> int:
        """Start an echo service on loopback and return its port."""
        server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Echo)
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return int(server.server_address[1])

    def start_qemu(self, name: str = "a") -> subprocess.Popen[bytes]:
        """A process whose arguments name the sandbox's domain, as QEMU's do."""
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(600)", "-name", f"guest=sbx-{name},x"]
        )
        self.addCleanup(process.wait)
        self.addCleanup(process.kill)
        # The kernel fills in the arguments a moment after exec returns to the parent.
        while b"guest=" not in Path(f"/proc/{process.pid}/cmdline").read_bytes():
            time.sleep(0.01)
        pidfile = self.runtime / "libvirt" / "qemu" / "run" / f"sbx-{name}.pid"
        pidfile.write_text(str(process.pid))
        return process

    def opener(self, pidfd: int, ports: Sequence[int]) -> list[socket.socket]:
        """Listen on the guest-side address in place of the sandbox's namespace."""
        del pidfd
        self.opened.append(ports)
        listeners: list[socket.socket] = []
        for port in ports:
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind((GUEST_SIDE, port))
            listener.listen()
            listeners.append(listener)
        return listeners

    def write(self, *entries: dict[str, object]) -> None:
        """Replace the list as workload-grantd does."""
        staged = self.state.with_name(".staged")
        staged.write_text(json.dumps({"grants": list(entries)}))
        staged.chmod(0o644)
        staged.replace(self.state)

    def pump(self, done: Callable[[], bool], limit: float = 5.0) -> None:
        """Run the event loop until `done` holds."""
        deadline = time.monotonic() + limit
        while not done():
            self.assertLess(time.monotonic(), deadline, "the proxy did not get there")
            self.proxy.step(0.02)

    def connect(self, port: int) -> socket.socket:
        """A guest connection through the proxy, checked with one round trip."""
        client = socket.create_connection((GUEST_SIDE, port), timeout=5)
        self.addCleanup(client.close)
        client.settimeout(0.0)
        self.assertEqual(self.round_trip(client), b"x\n")
        return client

    def round_trip(self, client: socket.socket) -> bytes:
        """Send one line and return what comes back: the echo, or b"" once cut."""
        try:
            client.sendall(b"x\n")
        except OSError:
            return b""
        received: list[bytes] = []

        def answered() -> bool:
            try:
                chunk = client.recv(64)
            except BlockingIOError:
                return False
            except OSError:
                return True
            received.append(chunk)
            return not chunk or b"".join(received).endswith(b"\n")

        self.pump(answered)
        return b"".join(received)

    def state_of(self, grant: str) -> str:
        """The proxy's state for one grant."""
        grants = cast("dict[str, dict[str, object]]", self.proxy.status()["grants"])
        return str(grants[grant]["state"])


class ProxyTest(Fixture):
    """Listeners and connections live exactly as long as their grant."""

    def test_revoke_cuts_only_its_grant(self) -> None:
        """A grant leaving the list closes its connections; another grant's keep working."""
        first, second = self.ports
        self.write(entry("00000001", first, 2000.0), entry("00000002", second, 2000.0))
        self.proxy.reconcile()
        self.assertEqual(self.state_of("00000001"), "listening")
        one, two = self.connect(first), self.connect(second)
        self.write(entry("00000002", second, 2000.0))
        self.pump(lambda: "00000001" not in str(self.proxy.status()))
        self.assertEqual(self.round_trip(one), b"")
        self.assertEqual(self.round_trip(two), b"x\n")
        with self.assertRaises(ConnectionRefusedError):
            socket.create_connection((GUEST_SIDE, first), timeout=5).close()

    def test_expiry_cuts(self) -> None:
        """At its deadline a grant's connections close, whether or not the list changed."""
        port = self.ports[0]
        self.write(entry("00000001", port, 1010.0))
        self.proxy.reconcile()
        client = self.connect(port)
        self.now = 1010.0
        self.proxy.step(0)
        self.assertEqual(self.round_trip(client), b"")
        self.assertEqual(self.proxy.status()["grants"], {})

    def test_emulator_exit_and_restore(self) -> None:
        """A stopped QEMU takes the listeners; the next one gets fresh ones."""
        port = self.ports[0]
        self.write(entry("00000001", port, 2000.0))
        self.proxy.reconcile()
        client = self.connect(port)
        self.qemu.kill()
        self.pump(lambda: self.state_of("00000001") == "waiting")
        self.assertEqual(self.round_trip(client), b"")
        self.start_qemu()
        self.now += vsock.RETRY
        self.pump(lambda: self.state_of("00000001") == "listening")
        self.connect(port)
        self.assertEqual(len(self.opened), 2)

    def test_fail_closed(self) -> None:
        """A replaced sandbox, a foreign pid, or an unreadable list exposes nothing."""
        port = self.ports[0]
        self.write(entry("00000001", port, 2000.0, token="f" * 16))
        self.proxy.reconcile()
        self.assertEqual(self.state_of("00000001"), "failed")
        self.write(entry("00000001", port, 2000.0))
        (self.runtime / "libvirt" / "qemu" / "run" / "sbx-a.pid").write_text(str(os.getpid()))
        self.proxy.reconcile()
        self.assertEqual(self.state_of("00000001"), "waiting")
        self.state.write_text("{")
        self.proxy.reconcile()
        self.assertEqual(self.proxy.status()["grants"], {})
        self.assertIn("malformed", str(self.proxy.status()["list_error"]))
        self.assertEqual(self.opened, [])

    def test_sync(self) -> None:
        """A sync request applies the list before it answers."""
        control_path = self.state.parent / "vsock.sock"
        control = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        control.bind(str(control_path))
        control.listen()
        proxy = self.proxy_with(control)
        self.addCleanup(control.close)
        self.write(entry("00000001", self.ports[0], 2000.0))
        answers: list[dict[str, object]] = []
        caller = threading.Thread(target=lambda: answers.append(vsock.sync(control_path)))
        caller.start()
        while caller.is_alive():
            proxy.step(0.02)
        grants = cast("dict[str, dict[str, object]]", answers[0]["grants"])
        self.assertEqual(grants["00000001"]["state"], "listening")
        with self.assertRaises(SbxError) as caught:
            vsock.sync(self.state.parent / "missing.sock")
        self.assertEqual(caught.exception.code, "vsock-proxy")


class RobustnessTest(Fixture):
    """No guest, client, or ordering of events takes the proxy or another grant down."""

    def test_deadline_fires_through_suspend_clock(self) -> None:
        """With nothing to retry, only the CLOCK_BOOTTIME timer wakes the loop at a deadline."""
        proxy = self.proxy_with(clock=vsock.boottime)
        self.write(entry("00000001", self.ports[0], vsock.boottime() + 0.3))
        proxy.reconcile()
        # Take the list's own inotify events first.
        proxy.step(0)
        timeout = proxy.timeout(vsock.boottime())
        self.assertIsNone(timeout)
        stepper = threading.Thread(target=proxy.step, args=(timeout,), daemon=True)
        stepper.start()
        stepper.join(5)
        self.assertFalse(stepper.is_alive(), "no timer woke the loop at the deadline")
        self.assertEqual(proxy.status()["grants"], {})

    def test_revoke_and_exit_in_one_round(self) -> None:
        """A list change that forgets the emulator leaves its pending exit event harmless."""
        self.write(entry("00000001", self.ports[0], 2000.0))
        self.proxy.reconcile()
        self.write()
        self.qemu.kill()
        self.qemu.wait()
        time.sleep(0.05)
        self.proxy.step(0.1)
        self.assertEqual(self.proxy.status()["grants"], {})
        self.assertEqual(self.proxy.emulators, {})

    def test_exit_and_connect_in_one_round(self) -> None:
        """A connection pending on a listener the exit closed is skipped, not accepted."""
        port = self.ports[0]
        self.write(entry("00000001", port, 2000.0))
        self.proxy.reconcile()
        self.qemu.kill()
        self.qemu.wait()
        client = socket.create_connection((GUEST_SIDE, port), timeout=5)
        self.addCleanup(client.close)
        time.sleep(0.05)
        self.proxy.step(0.1)
        self.assertEqual(self.state_of("00000001"), "waiting")

    def test_partial_placement_fails(self) -> None:
        """Fewer listeners than ports is a failed placement, not a listening grant."""
        first, second = sorted(self.ports)

        def short(pidfd: int, ports: Sequence[int]) -> list[socket.socket]:
            return self.opener(pidfd, ports[:1])

        self.proxy.opener = short
        ranges = [{"from": first, "to": first}, {"from": second, "to": second}]
        self.write(entry("00000001", first, 2000.0, ports=ranges))
        self.proxy.reconcile()
        self.assertEqual(self.state_of("00000001"), "failed")
        with self.assertRaises(ConnectionRefusedError):
            socket.create_connection((GUEST_SIDE, first), timeout=5).close()

    def test_replaced_during_lookup(self) -> None:
        """A creation token that changes while the emulator is looked up fails the placement."""
        creation = self.paths.sandbox("a") / "creation"
        found = vsock.open_emulator

        def replacing(runtime: Path, sandbox: str) -> vsock.Emulator | None:
            running = found(runtime, sandbox)
            creation.write_text("e" * 16)
            return running

        self.write(entry("00000001", self.ports[0], 2000.0))
        with unittest.mock.patch("sbx.vsock.open_emulator", replacing):
            self.proxy.reconcile()
        self.assertEqual(self.state_of("00000001"), "failed")
        self.assertEqual((self.proxy.emulators, self.opened), ({}, []))

    def test_descriptor_exhaustion(self) -> None:
        """A full descriptor table pauses accepting; the proxy and other grants live on."""
        first, second = self.ports
        self.write(entry("00000001", first, 2000.0), entry("00000002", second, 2000.0))
        self.proxy.reconcile()
        other = self.connect(second)
        backlog = [socket.create_connection((GUEST_SIDE, first), timeout=5) for _ in range(3)]
        for client in backlog:
            self.addCleanup(client.close)
        # One descriptor left: the accept takes it, and the upstream socket finds none.
        used = len(list(Path("/proc/self/fd").iterdir()))
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        resource.setrlimit(resource.RLIMIT_NOFILE, (used + 1, hard))
        try:
            for _ in range(3):
                self.proxy.step(0.02)
        finally:
            resource.setrlimit(resource.RLIMIT_NOFILE, (soft, hard))
        served = self.proxy.served["00000001"]
        self.assertIn("Too many open files", str(served.accept_error))
        self.assertFalse(served.accepting)
        self.assertEqual(self.round_trip(other), b"x\n")
        self.now += vsock.RETRY
        self.proxy.step(0)
        self.connect(first)

    def test_connection_caps(self) -> None:
        """At a grant's cap, and at its sandbox's, new connections wait in the backlog."""
        first, second = self.ports
        cap = 2
        proxy = self.proxy_with(grant_connections=cap, sandbox_connections=cap + 1)
        self.proxy = proxy
        self.write(entry("00000001", first, 2000.0), entry("00000002", second, 2000.0))
        proxy.reconcile()
        one, _ = self.connect(first), self.connect(first)
        waiting = socket.create_connection((GUEST_SIDE, first), timeout=5)
        self.addCleanup(waiting.close)
        self.connect(second)
        held = socket.create_connection((GUEST_SIDE, second), timeout=5)
        self.addCleanup(held.close)
        for _ in range(10):
            proxy.step(0.02)
        self.assertEqual([len(served.pipes) for served in proxy.served.values()], [2, 1])
        one.close()
        self.pump(lambda: len(proxy.served["00000001"].pipes) == cap)
        waiting.settimeout(0.0)
        self.assertEqual(self.round_trip(waiting), b"x\n")

    def test_no_host_address(self) -> None:
        """A `bind = "any"` grant without a host address closes the guest's connection."""
        port = self.ports[0]
        self.proxy = self.proxy_with(resolve=lambda _bind: None)
        self.write(entry("00000001", port, 2000.0, bind="any"))
        self.proxy.reconcile()
        client = socket.create_connection((GUEST_SIDE, port), timeout=5)
        self.addCleanup(client.close)
        client.settimeout(0.0)
        self.assertEqual(self.round_trip(client), b"")
        self.assertIn("no non-loopback", str(self.proxy.served["00000001"].accept_error))
        self.assertEqual(vsock.destination("loopback"), vsock.LOOPBACK)
        self.assertNotEqual(vsock.destination("any"), vsock.LOOPBACK)

    def test_dribbling_control_client(self) -> None:
        """A control client that sends slowly never holds the loop past one round."""
        control_path = self.state.parent / "vsock.sock"
        control = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        control.bind(str(control_path))
        control.listen()
        self.addCleanup(control.close)
        proxy = self.proxy_with(control)
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(client.close)
        client.connect(str(control_path))
        client.send(b" ")
        started = time.monotonic()
        for _ in range(5):
            proxy.step(0.1)
        self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(len(proxy.requests), 1)
        with unittest.mock.patch("sbx.vsock.time.monotonic", return_value=started + 3600):
            proxy.step(0)
        self.assertEqual(proxy.requests, {})


class PlacementTest(unittest.TestCase):
    """The forked child reports failures without leaving descriptors behind."""

    def test_failure_reaches_the_parent(self) -> None:
        """Joining a process's namespaces that the caller already holds fails as vsock-place."""
        process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"])
        self.addCleanup(process.wait)
        self.addCleanup(process.kill)
        pidfd = os.pidfd_open(process.pid)
        self.addCleanup(os.close, pidfd)
        before = len(list(Path("/proc/self/fd").iterdir()))
        with self.assertRaises(SbxError) as caught:
            vsock.open_listeners(pidfd, [5000])
        self.assertEqual(caught.exception.code, "vsock-place")
        self.assertEqual(len(list(Path("/proc/self/fd").iterdir())), before)
