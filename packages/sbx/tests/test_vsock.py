# Copyright (c) 2026 Bad3r
"""The vsock grant proxy over TCP stand-ins for the in-namespace listeners."""

import json
import os
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
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
        self.proxy = vsock.Proxy(
            None,
            state=self.state,
            runtime=self.runtime,
            paths=self.paths,
            opener=self.opener,
            clock=lambda: self.now,
            owner=os.getuid(),
        )
        self.addCleanup(self.proxy.close)

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
        proxy = vsock.Proxy(
            control,
            state=self.state,
            runtime=self.runtime,
            paths=self.paths,
            opener=self.opener,
            clock=lambda: self.now,
            owner=os.getuid(),
        )
        self.addCleanup(proxy.close)
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
