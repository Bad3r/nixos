# Copyright (c) 2026 Bad3r
"""Policy and lifecycle checks of sbx against a fake backend and stub tools."""

import base64
import dataclasses
import itertools
import json
import os
import shlex
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast
from unittest import mock

from sbx import (
    admission,
    agent,
    cli,
    config,
    context,
    domain,
    errors,
    execution,
    fsutil,
    gui,
    keys,
    lifecycle,
    model,
    net,
    ops,
    pipeline,
    prepare,
    proc,
    storage,
)
from sbx.cloud import CloudImage
from sbx.config import Egress, Paths, Settings, Tools
from sbx.errors import SbxError
from sbx.model import NS, DomainInfo, ExecOptions, Meta
from sbx.results import GcAction, Results
from sbx.sandboxes import Sandboxes

if TYPE_CHECKING:
    from collections.abc import Callable

NOW = 1_800_000_000
EMULATOR = "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-sbx-qemu"
MAC = "52:54:00:ab:cd:ef"


def dispatch(sandboxes: Sandboxes, *argv: str) -> tuple[object, int]:
    """Run one verb through the command line's parser and the operation layer, in JSON mode.

    A failure raises its error.
    """
    operation, args = cli.parse(argv)
    outcome = ops.invoke(operation, lambda _session: sandboxes, args, ops.Ctx(sandboxes.session))
    if isinstance(outcome, ops.Failure):
        raise outcome.error
    return outcome.as_json(), outcome.exit_status()


STUBS = {
    "ssh-keygen": 'for k; do :; done; echo key > "$k"; echo "ssh-ed25519 AAAA sbx" > "$k.pub"',
    "nix-store": 'ln -s "$4" "$2"',
    "qemu-img": (
        'case "$1" in info) [ -n "$SBX_TEST_IMAGE_INFO" ] '
        "|| exec echo '{\"virtual-size\": 1073741824}'; "
        '[ "$SBX_TEST_IMAGE_INFO" = fail ] && exit 1; echo "$SBX_TEST_IMAGE_INFO";; '
        'convert) for t; do :; done; touch "$t";; '
        '*) eval "disk=\\${$(($# - 1))}"; touch "$disk";; esac'
    ),
    "ssh": (
        'if [ -n "$SBX_TEST_SSH_LOG" ]; then printf "%s\\n" "$@" > "$SBX_TEST_SSH_LOG"; fi; '
        'case "$*" in *poweroff*) code="${SBX_TEST_PROVISION_EXIT:-0}"; '
        '[ "$code" = 0 ] && touch "$SBX_TEST_POWEROFF"; exit "$code";; '
        '*blockme*) touch "$SBX_TEST_GATE.started"; '
        'while [ ! -e "$SBX_TEST_GATE" ]; do sleep 0.05; done;; esac; '
        'exit "${SBX_TEST_SSH_EXIT:-0}"'
    ),
    "xorriso": (
        'for a; do [ "$prev" = -output ] && out=$a; prev=$a; done; '
        'rm -rf "$SBX_TEST_SEED"; cp -r "$a" "$SBX_TEST_SEED"; touch "$out"'
    ),
    "nix": (
        'printf "%s\\n" "$@" > "$SBX_TEST_NIX_LOG"; echo "{\\"storePath\\": \\"$SBX_TEST_IMAGE\\"}"'
    ),
    "scp": (
        'printf "%s\\n" "$@" > "$SBX_TEST_LOG"; for t; do :; done; '
        'case "$t" in root@*) exit 0;; esac; '
        'case "$*" in *missing*) echo "scp: no such file" >&2; exit 1;; esac; '
        'if [ -n "$SBX_TEST_BIG" ]; then exec head -c "$SBX_TEST_BIG" /dev/zero > "$t"; fi; '
        'if [ -n "$SBX_TEST_MANY" ]; then mkdir "$t"; for i in 1 2 3 4 5 6; do '
        'head -c "$SBX_TEST_MANY" /dev/urandom > "$t/$i"; sleep 0.4; done; '
        'touch "$SBX_TEST_DONE"; exit 0; fi; '
        'echo out > "$t"; chmod 755 "$t"'
    ),
    "git": (
        'if [ -n "$GIT_DIR" ] || [ -z "$SBX_TEST_TOPLEVEL" ]; then exit 1; fi; '
        'echo "$SBX_TEST_TOPLEVEL"'
    ),
    "other": "exit 0",
    "timedatectl": 'echo "${SBX_TEST_NTP:-yes}"',
}


class FakeBackend:
    """Session domains held in memory."""

    def __init__(self) -> None:
        """Start empty."""
        self.domains_by_name: dict[str, DomainInfo] = {}
        self.xml: dict[str, str] = {}
        self.replies: list[dict[str, Any]] = []
        self.keys: list[tuple[str, list[int]]] = []
        self.addresses = ["172.16.2.5"]
        # Host sleep: domains that refuse, unconnected agent answers left, saved states.
        self.failing: set[str] = set()
        # Domains another client removed after the listing.
        self.vanished: set[str] = set()
        self.unconnected: dict[str, int] = {}
        self.synced: list[str] = []
        self.saved_state: dict[str, str] = {}
        # Polls of job_active left before a domain's save job finishes.
        self.jobs: dict[str, int] = {}
        # When set, managed_save calls it, then blocks until abort_job.
        self.before_save: Callable[[], None] | None = None
        self.held = threading.Event()
        self.aborted: list[str] = []
        # guest-exec without queued replies: the argv and stdin of each, and its exit.
        self.execs: list[tuple[list[str], bytes]] = []
        self.statuses: dict[int, dict[str, Any]] = {}
        self.exit_status: dict[str, Any] = {"exitcode": 0}
        # Screenshots taken, and the bytes of each thread's latest one.
        self.lock = threading.Lock()
        self.captures = 0
        self.captured: dict[int, bytes] = {}

    def domains(self) -> list[DomainInfo]:
        """List the fake domains; a provisioning run over SSH has powered them all off."""
        if Path(os.environ["SBX_TEST_POWEROFF"]).exists():
            for name in list(self.domains_by_name):
                self.stop(name)
        return list(self.domains_by_name.values())

    def domain(self, domain: str) -> DomainInfo | None:
        """Describe one fake domain, after the same poweroff check as the listing."""
        if Path(os.environ["SBX_TEST_POWEROFF"]).exists() and domain in self.domains_by_name:
            self.stop(domain)
        return self.domains_by_name.get(domain)

    def add(self, name: str, *, expires: int, active: bool = True, **kwargs: Any) -> None:  # noqa: ANN401
        """Insert a domain as if sbx had created it."""
        meta = Meta(
            kwargs.get("base", "nixos"),
            "/nix/store/x/sbx.qcow2",
            "none",
            NOW - 60,
            expires,
            kwargs.get("session"),
        )
        self.domains_by_name[f"sbx-{name}"] = DomainInfo(
            name=f"sbx-{name}",
            state="running" if active else "shutoff",
            active=active,
            memory_mib=kwargs.get("memory", 2048),
            cpus=2,
            cid=3 if active else None,
            meta=meta,
            managed_save=kwargs.get("managed_save", False),
            pid=4242 if active else None,
            emulator=kwargs.get("emulator", EMULATOR),
        )

    def start(self, xml: str) -> None:
        """Record the XML and treat the domain as running."""
        root = ET.fromstring(xml)  # noqa: S314
        name = root.findtext("name", "")
        element = root.find(f"metadata/{{{NS}}}sandbox")
        if element is None:
            raise AssertionError
        mac = root.find("devices/interface[@type='bridge']/mac")
        self.xml[name] = xml
        self.domains_by_name[name] = DomainInfo(
            name=name,
            state="running",
            active=True,
            memory_mib=int(root.findtext("memory", "0")),
            cpus=2,
            cid=3,
            meta=Meta.parse(element),
            managed_save=False,
            mac=None if mac is None else mac.get("address"),
            pid=4242,
            emulator=root.findtext("devices/emulator"),
        )

    def remove(self, domain: str) -> None:
        """Forget a domain; one already gone counts as removed."""
        self.domains_by_name.pop(domain, None)

    def agent(self, domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:  # noqa: ARG002
        """Answer guest-ping and guest-network-get-interfaces, then the queued replies."""
        if command["execute"] == "guest-ping":
            return {"return": {}}
        if command["execute"] == "guest-network-get-interfaces":
            addresses = [{"ip-address-type": "ipv4", "ip-address": a} for a in self.addresses]
            nic = {"name": "eth0", "hardware-address": MAC.upper(), "ip-addresses": addresses}
            return {"return": [{"name": "lo", "hardware-address": "00:00:00:00:00:00"}, nic]}
        if self.replies:
            return self.replies.pop(0)
        arguments = cast("dict[str, Any]", command["arguments"])
        if command["execute"] == "guest-exec":
            stdin = base64.b64decode(arguments.get("input-data", ""))
            argv = [arguments["path"], *arguments["arg"]]
            self.execs.append((argv, stdin))
            if "blockme" in argv:
                gate = Path(os.environ["SBX_TEST_GATE"])
                gate.with_name("gate.started").touch()
                while not gate.exists():
                    time.sleep(0.05)
            pid = 100 + len(self.execs)
            self.statuses[pid] = {"exited": True, **self.exit_status}
            return {"return": {"pid": pid}}
        return {"return": self.statuses.pop(arguments["pid"])}

    def live_xml(self, domain: str) -> str:
        """The definition a domain started with, or an empty one."""
        return self.xml.get(domain, "<domain><devices/></domain>")

    def screenshot(self, domain: str, target: Path) -> str:  # noqa: ARG002
        """Write a placeholder image of its own to a new file, recorded by the calling thread."""
        with self.lock:
            self.captures += 1
            data = f"png {self.captures}".encode()
        self.captured[threading.get_ident()] = data
        with target.open("xb") as out:
            out.write(data)
        return "image/png"

    def send_key(self, domain: str, keycodes: Any, holdtime: int) -> None:  # noqa: ANN401, ARG002
        """Record one chord."""
        self.keys.append((domain, list(keycodes)))

    def stop(self, domain: str) -> None:
        """Turn a domain off, as a guest poweroff does."""
        info = self.domains_by_name[domain]
        self.domains_by_name[domain] = dataclasses.replace(
            info, state="shutoff", active=False, cid=None
        )

    def _set(self, domain: str, state: str, *, active: bool, managed_save: bool) -> None:
        if domain in self.failing:
            msg = f"{domain} refused"
            raise SbxError(msg, code="libvirt")
        if domain in self.vanished:
            msg = f"no domain {domain}"
            raise SbxError(msg, code="not-found")
        info = self.domains_by_name[domain]
        self.domains_by_name[domain] = dataclasses.replace(
            info, state=state, active=active, managed_save=managed_save
        )

    def suspend(self, domain: str) -> None:
        """Pause a domain."""
        self._set(domain, "paused", active=True, managed_save=False)

    def resume(self, domain: str) -> None:
        """Continue a domain."""
        self._set(domain, "running", active=True, managed_save=False)

    def managed_save(self, domain: str) -> None:
        """Stop a domain with a managed save."""
        if self.before_save is not None:
            self.before_save()
            self.held.wait(10)
            if domain in self.aborted:
                msg = "operation aborted"
                raise SbxError(msg, code="libvirt")
        state = self.domains_by_name[domain].state
        self._set(domain, "shutoff", active=False, managed_save=True)
        self.saved_state[domain] = state

    def restore(self, domain: str) -> None:
        """Start a domain in the state it was saved in, as libvirt does."""
        self._set(domain, self.saved_state.pop(domain, "running"), active=True, managed_save=False)

    def job_active(self, domain: str) -> bool:
        """Report a save job until its polls run out, then finish the save."""
        left = self.jobs.get(domain)
        if left is None:
            return False
        if left > 0:
            self.jobs[domain] = left - 1
            return True
        del self.jobs[domain]
        self.managed_save(domain)
        return False

    def abort_job(self, domain: str) -> None:
        """Abort a blocked save."""
        self.aborted.append(domain)
        self.held.set()

    def set_time(self, domain: str) -> None:
        """Answer once the agent has connected."""
        if self.unconnected.get(domain, 0) > 0:
            self.unconnected[domain] -= 1
            msg = "agent not connected"
            raise SbxError(msg, code="agent-unresponsive")
        self.synced.append(domain)


class Fixture(unittest.TestCase):
    """Stub tools, a built base, a state directory, and a fake backend."""

    def setUp(self) -> None:
        """Lay out stub tools, a built base, and a state directory."""
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.scratch = Path(scratch.name)
        stubs = self.scratch / "stubs"
        stubs.mkdir()
        for name, body in STUBS.items():
            path = stubs / name
            path.write_text(f"#!/bin/sh\n{body}\n")
            path.chmod(0o755)
        other = str(stubs / "other")
        tools = Tools(
            emulator=EMULATOR,
            qemu_img=str(stubs / "qemu-img"),
            ssh=str(stubs / "ssh"),
            scp=str(stubs / "scp"),
            ssh_keygen=str(stubs / "ssh-keygen"),
            socat=other,
            tesseract=other,
            nsenter="/nix/store/util-linux/bin/nsenter",
            git=str(stubs / "git"),
            systemctl=other,
            nix=str(stubs / "nix"),
            nix_store=str(stubs / "nix-store"),
            timedatectl=str(stubs / "timedatectl"),
            xorriso=str(stubs / "xorriso"),
            virtiofsd="/nix/store/virtiofsd/bin/virtiofsd",
        )
        self.settings = Settings(
            running=3,
            memory_mib=12 * 1024,
            sandbox_memory_mib=6144,
            sandbox_cpus=8,
            max_ttl=24 * 3600,
            disk_cap_bytes=30 << 30,
            min_free_bytes=0,
            default_memory_mib=2048,
            default_gui_memory_mib=4096,
            default_cpus=2,
            default_ttl=2 * 3600,
            disk_gib=8,
            cpuset="8-23",
            flake="/flake",
            unit="sbx-libvirt.service",
            slice="sbx.slice",
            output_limit=1024,
            boot_timeout=5,
            egress="no egress network",
            cloud_images={"debian-13": CloudImage("https://cloud.example/d.qcow2", "sha256-x")},
            tools=tools,
        )
        self.paths = Paths(self.scratch / "data" / "sbx", self.scratch / "config")
        image = self.scratch / "store" / "base"
        image.mkdir(parents=True)
        (image / "sbx-nixos.qcow2").write_bytes(b"")
        self.paths.bases.mkdir(parents=True)
        (self.paths.bases / "nixos").symlink_to(image)
        (self.paths.bases / "nixos-gui").symlink_to(image)
        self.backend = FakeBackend()
        self.environment = mock.patch.dict(
            os.environ,
            {
                "TMPDIR": str(self.scratch / "tmp"),
                "SBX_TEST_LOG": str(self.scratch / "scp.log"),
                "SBX_TEST_DONE": str(self.scratch / "scp.done"),
                "SBX_TEST_SEED": str(self.scratch / "seed"),
                "SBX_TEST_POWEROFF": str(self.scratch / "poweroff"),
                "SBX_TEST_NIX_LOG": str(self.scratch / "nix.log"),
                "SBX_TEST_IMAGE": str(image / "sbx-nixos.qcow2"),
            },
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        (self.scratch / "tmp").mkdir()
        journal = mock.patch.object(context.journal, "record")
        self.journal_record = journal.start()
        self.addCleanup(journal.stop)
        grants = mock.patch.object(net, "GRANT_SOCKET", self.scratch / "grant.sock")
        grants.start()
        self.addCleanup(grants.stop)

    def sandboxes(self, session: str | None = "claude:one") -> Sandboxes:
        """Bind the fake backend at a fixed clock."""
        return Sandboxes(
            self.settings, self.paths, lambda _slice: self.backend, session, lambda: NOW
        )

    def request(self, base: str = "nixos", /, **overrides: Any) -> model.Request:  # noqa: ANN401
        """Validate create flags with defaults."""
        flags: dict[str, Any] = {
            "name": "t1",
            "net": "none",
            "memory": None,
            "cpus": None,
            "ttl": None,
        }
        flags.update(overrides)
        return self.sandboxes().request(base, **flags)


class SandboxesTest(Fixture):
    """Ceilings, rendering, removal, and copy roots."""

    def test_parsers(self) -> None:
        """Durations and sizes accept their units."""
        self.assertEqual(config.parse_duration("90"), 90)
        self.assertEqual(config.parse_duration("30m"), 1800)
        self.assertEqual(config.parse_duration("2h"), 7200)
        self.assertEqual(config.parse_memory("2G"), 2048)
        self.assertEqual(config.parse_memory("512m"), 512)
        with self.assertRaises(SbxError):
            config.parse_duration("2 hours")

    def test_request_ceilings(self) -> None:
        """Values above a ceiling and unknown names or networks are refused."""
        request = self.request()
        self.assertEqual((request.memory_mib, request.cpus, request.ttl), (2048, 2, 7200))
        for overrides in (
            {"memory": "8G"},
            {"cpus": 9},
            {"ttl": "25h"},
            {"ttl": "10s"},
            {"name": "bases"},
            {"name": "Upper"},
            {"net": "lan"},
        ):
            with self.subTest(overrides=overrides), self.assertRaises(SbxError):
                self.request(**overrides)

    def test_create_renders_an_untrusted_domain(self) -> None:
        """The domain has no NIC, no vdagent, a disposable disk, and the root key credential."""
        result = self.sandboxes().create(self.request(ttl="1h"))
        self.assertEqual((result.name, result.ttl_left, result.session), ("t1", 3600, "claude:one"))
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        self.assertIsNone(root.find("devices/interface"))
        self.assertIsNone(root.find("devices/graphics"))
        channels = [target.get("name") for target in root.iterfind("devices/channel/target")]
        self.assertEqual(channels, ["org.qemu.guest_agent.0"])
        self.assertEqual(root.find("devices/disk/driver").get("cache"), "unsafe")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("devices/vsock/cid").get("auto"), "yes")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("vcpu").get("cpuset"), "8-23")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("cputune/emulatorpin").get("cpuset"), "8-23")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("cpu/feature").get("name"), "vmx")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("features/vmport").get("state"), "off")  # pyright: ignore[reportOptionalMemberAccess]
        entry = root.find("sysinfo/entry")
        self.assertEqual(entry.get("name"), domain.CREDENTIAL)  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(entry.text, "ssh-ed25519 AAAA sbx")  # pyright: ignore[reportOptionalMemberAccess]
        directory = self.paths.sandbox("t1")
        self.assertTrue((directory / "disk.qcow2").exists())
        self.assertTrue((directory / "base").is_symlink())
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request())
        self.assertEqual(refused.exception.code, "exists")

    def test_running_and_memory_ceilings(self) -> None:
        """A fourth sandbox, or one past 12 GiB declared, is refused."""
        for index in range(3):
            self.backend.add(f"r{index}", expires=NOW + 60)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request())
        self.assertEqual(refused.exception.code, "over-limit")
        self.backend.remove("sbx-r1")
        self.backend.remove("sbx-r2")
        self.backend.add("big", expires=NOW + 60, memory=6144)
        with self.assertRaises(SbxError):
            self.sandboxes().create(self.request(memory="6G"))
        self.sandboxes().create(self.request(memory="2G"))

    def test_disk_floor(self) -> None:
        """Too little free space on the state filesystem refuses create."""
        self.settings = dataclasses.replace(self.settings, min_free_bytes=1 << 62)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request())
        self.assertEqual(refused.exception.code, "disk-full")
        self.assertFalse(self.paths.sandbox("t1").exists())

    def test_ssh_enters_the_qemu_namespace(self) -> None:
        """SSH reaches the guest's CID from inside its QEMU's namespaces, never the host's."""
        self.add_running("v")
        sandboxes = self.sandboxes()
        log = self.scratch / "ssh.log"
        with mock.patch.dict(os.environ, {"SBX_TEST_SSH_LOG": str(log)}):
            sandboxes.exec_attached("v", ["true"], ExecOptions())
        proxy = next(arg for arg in log.read_text().splitlines() if arg.startswith("ProxyCommand="))
        self.assertEqual(
            proxy,
            "ProxyCommand=/nix/store/util-linux/bin/nsenter --target 4242 --user --net "
            f"--preserve-credentials -- {self.settings.tools.socat} - VSOCK-CONNECT:3:22",
        )
        self.backend.domains_by_name["sbx-v"] = dataclasses.replace(
            self.backend.domains_by_name["sbx-v"], pid=None
        )
        with self.assertRaises(SbxError) as refused:
            sandboxes.exec_attached("v", ["true"], ExecOptions())
        self.assertEqual(refused.exception.code, "not-running")

    def test_gc(self) -> None:
        """Expired, stopped, and directory-less sandboxes go; saves, prepares, live ones stay."""
        for name in ("live", "old", "off", "saved", "prepare-debian-13"):
            self.paths.sandbox(name).mkdir(parents=True)
        self.backend.add("live", expires=NOW + 60)
        self.backend.add("prepare-debian-13", expires=NOW + 60, active=False)
        self.backend.add("old", expires=NOW - 1)
        self.backend.add("off", expires=NOW + 60, active=False)
        self.backend.add("saved", expires=NOW + 60, active=False, managed_save=True)
        self.backend.add("lost", expires=NOW + 60)
        self.paths.sandbox("stray").mkdir()
        sandboxes = self.sandboxes()
        planned = sandboxes.gc(dry_run=True)
        self.assertEqual(len(self.backend.domains()), 6)
        self.assertTrue(self.paths.sandbox("stray").exists())
        self.assertEqual(sandboxes.gc(dry_run=False), planned)
        reasons = {action.name: action.reason for action in planned}
        self.assertEqual(
            reasons,
            {
                "old": "expired",
                "off": "shut off",
                "lost": "run directory missing",
                "stray": "no domain",
            },
        )
        self.assertEqual(
            sorted(self.backend.domains_by_name), ["sbx-live", "sbx-prepare-debian-13", "sbx-saved"]
        )
        self.assertFalse(self.paths.sandbox("stray").exists())

    def serve_grants(self, answer: dict[str, object]) -> list[dict[str, object]]:
        """Answer one request on the patched grant socket and keep it."""
        requests: list[dict[str, object]] = []
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(net.GRANT_SOCKET))
        server.listen(1)
        self.addCleanup(server.close)

        def handle() -> None:
            connection, _ = server.accept()
            with connection:
                requests.append(json.loads(b"".join(iter(lambda: connection.recv(4096), b""))))
                connection.sendall(json.dumps(answer).encode())

        thread = threading.Thread(target=handle)
        thread.start()
        self.addCleanup(thread.join)
        return requests

    def test_destroy_revokes_grants(self) -> None:
        """Destroying a sandbox revokes its grants by name."""
        requests = self.serve_grants({"revoked": ["0000000a"]})
        self.paths.sandbox("g").mkdir(parents=True)
        self.backend.add("g", expires=NOW + 60)
        self.assertEqual(self.sandboxes().destroy("g"), ["g"])
        self.assertEqual(requests, [{"verb": "revoke", "source": "sbx-g"}])

    def test_destroy_reports_live_grants(self) -> None:
        """A refused revoke is journaled and the sandbox is still destroyed."""
        self.serve_grants({"error": {"code": "nft", "message": "no table"}})
        self.paths.sandbox("g").mkdir(parents=True)
        self.backend.add("g", expires=NOW + 60)
        with mock.patch("sys.stderr") as stderr:
            self.assertEqual(self.sandboxes().destroy("g"), ["g"])
        self.assertNotIn("sbx-g", self.backend.domains_by_name)
        self.assertIn("grants of g stay live", str(self.journal_record.call_args_list))
        self.assertTrue(stderr.write.called)

    def test_destroy_reopens_closed_directories(self) -> None:
        """Directories a guest closed under shared go too, and grants go even when they stay."""
        closed = self.paths.sandbox("g") / "shared" / "d" / "closed"
        closed.mkdir(parents=True)
        (closed / "f").write_text("guest")
        closed.chmod(0)
        closed.parent.chmod(0)
        self.backend.add("g", expires=NOW + 60)
        with mock.patch.object(storage, "revoke_grants") as revoke:
            self.assertEqual(self.sandboxes().destroy("g"), ["g"])
            self.assertFalse(self.paths.sandbox("g").exists())
            self.paths.sandbox("h").mkdir(parents=True)
            with (
                mock.patch.object(storage.shutil, "rmtree", side_effect=PermissionError("held")),
                self.assertRaises(PermissionError),
            ):
                self.sandboxes().destroy("h")
        self.assertEqual([call.args[0] for call in revoke.call_args_list], ["g", "h"])

    def test_usage_counts_closed_directories(self) -> None:
        """A directory a guest closed under shared counts; one left unreadable fails closed."""
        closed = self.paths.sandbox("g") / "shared" / "closed"
        closed.mkdir(parents=True)
        (closed / "big").write_bytes(b"x" * (64 << 10))
        closed.chmod(0)
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=32 << 10)
        problem = self.sandboxes().disk_problem()
        self.assertIn("cap", str(problem))
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=1 << 30)
        self.assertIsNone(self.sandboxes().disk_problem())
        hidden = self.paths.sandbox("g") / "hidden"
        hidden.mkdir()
        hidden.chmod(0)
        self.addCleanup(hidden.chmod, 0o700)
        self.assertIn("cannot be measured", str(self.sandboxes().disk_problem()))

    def test_grants_follow_removals(self) -> None:
        """Token removals revoke only what they remove; gc revokes orphaned directories too."""
        with mock.patch.object(storage, "revoke_grants") as revoke:
            self.sandboxes().create(self.request(), token="tok")  # noqa: S106
            sandboxes = self.sandboxes()
            self.assertEqual(sandboxes.destroy_created("other"), [])
            revoke.assert_not_called()
            self.assertEqual(sandboxes.destroy_created("tok"), ["t1"])
            self.assertEqual([call.args[0] for call in revoke.call_args_list], ["t1"])
            self.paths.sandbox("orphan").mkdir(parents=True)
            sandboxes.gc(dry_run=False)
            self.assertEqual(revoke.call_args_list[-1].args, ("orphan", None))

    def test_gc_with_an_unsynced_clock(self) -> None:
        """Without NTP sync, gc keeps expired sandboxes and still applies its other reasons."""
        for name in ("old", "off"):
            self.paths.sandbox(name).mkdir(parents=True)
        self.backend.add("old", expires=NOW - 1)
        self.backend.add("off", expires=NOW - 1, active=False)
        with mock.patch.dict(os.environ, {"SBX_TEST_NTP": "no"}):
            removed = self.sandboxes().gc(dry_run=False)
        self.assertEqual(removed, [GcAction("off", "shut off")])
        self.assertEqual(sorted(self.backend.domains_by_name), ["sbx-old"])

    def test_destroy_mine(self) -> None:
        """--mine removes only the caller's sandboxes."""
        for name, session in (("a", "claude:one"), ("b", "codex:two")):
            self.paths.sandbox(name).mkdir(parents=True)
            self.backend.add(name, expires=NOW + 60, session=session)
        self.assertEqual(self.sandboxes().destroy_where(mine=True, expired=False), ["a"])
        self.assertEqual(sorted(self.backend.domains_by_name), ["sbx-b"])
        with self.assertRaises(SbxError):
            self.sandboxes(session=None).listing(mine=True)

    def test_find_skips_the_listing(self) -> None:
        """One sandbox's verbs look it up alone, so other domains cannot fail them."""
        self.backend.add("a", expires=NOW + 60)
        with mock.patch.object(self.backend, "domains", side_effect=AssertionError):
            self.assertEqual(self.sandboxes().find("a").name, "a")
            with self.assertRaises(SbxError) as raised:
                self.sandboxes().find("b")
        self.assertEqual(raised.exception.code, "not-found")

    def test_destroy_created(self) -> None:
        """A creation token reaches the metadata and selects only its own sandbox."""
        self.sandboxes().create(self.request(), token="tok")  # noqa: S106
        self.sandboxes().create(self.request(name="t2"))
        self.assertEqual(self.sandboxes().destroy_created("other"), [])
        self.assertEqual(self.sandboxes().destroy_created("tok"), ["t1"])
        self.assertEqual(sorted(self.backend.domains_by_name), ["sbx-t2"])

    def test_run_spares_a_namesake(self) -> None:
        """A run whose sandbox is destroyed and renamed mid-command never touches the namesake."""
        gate = self.scratch / "gate"
        argv = ["run", "nixos", "--name=r", "--out=/root/x", f"--to={self.scratch / 'tmp'}"]
        failures: list[SbxError] = []

        def worker() -> None:
            try:
                self.dispatch(*argv, "--", "blockme")
            except SbxError as error:
                failures.append(error)

        with mock.patch.dict(os.environ, {"SBX_TEST_GATE": str(gate)}):
            thread = threading.Thread(target=worker)
            thread.start()
            started = gate.with_name("gate.started")
            deadline = time.monotonic() + 5
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            other = self.sandboxes(session="claude:two")
            other.destroy("r")
            replacement = other.create(self.request(name="r"))
            gate.touch()
            thread.join(5)
        (error,) = failures
        self.assertEqual((error.code, error.details["phase"]), ("run-incomplete", "out"))
        run = cast("dict[str, Any]", error.details["run"])
        self.assertEqual(run["out"][0]["error"]["code"], "replaced")
        self.assertEqual(run["cleanup"], {"destroyed": [], "error": None})
        self.assertEqual(
            cast("Meta", self.backend.domains_by_name["sbx-r"].meta).token, replacement.token
        )
        self.assertTrue(self.paths.sandbox("r").is_dir())

    def test_destroy_expired_unsynced(self) -> None:
        """--expired refuses while the host clock is unsynced."""
        self.paths.sandbox("old").mkdir(parents=True)
        self.backend.add("old", expires=NOW - 60)
        with (
            mock.patch.dict(os.environ, {"SBX_TEST_NTP": "no"}),
            self.assertRaises(SbxError) as caught,
        ):
            self.sandboxes().destroy_where(mine=False, expired=True)
        self.assertEqual(caught.exception.code, "clock-unsynced")
        self.assertEqual(sorted(self.backend.domains_by_name), ["sbx-old"])

    def test_copy_roots(self) -> None:
        """Copies in come from the roots only, and copies out default to xfer."""
        self.paths.sandbox("c").mkdir(parents=True)
        (self.paths.sandbox("c") / "xfer").mkdir()
        self.backend.add("c", expires=NOW + 60)
        sandboxes = self.sandboxes()
        inside = self.scratch / "tmp" / "work"
        inside.mkdir()
        (inside / "file").write_text("x")
        result = sandboxes.copy(str(inside), "c:/root/")
        self.assertEqual(result.target, "c:/root/")
        outside = self.scratch / "secret"
        outside.write_text("x")
        with self.assertRaises(SbxError) as refused:
            sandboxes.copy(str(outside), "c:/root/")
        self.assertEqual(refused.exception.code, "path-denied")
        (inside / "escape").symlink_to(outside)
        with self.assertRaises(SbxError):
            sandboxes.copy(str(inside), "c:/root/")
        result = sandboxes.copy("c:/var/log/messages", None)
        self.assertEqual(result.target, str(self.paths.sandbox("c") / "xfer" / "messages"))
        with self.assertRaises(SbxError):
            sandboxes.copy("c:/etc/passwd", str(outside))

    def checkout_root(self, toplevel: Path, **environment: str) -> Path | None:
        """Return the checkout root sbx derives from a reported toplevel."""
        with mock.patch.dict(os.environ, {"SBX_TEST_TOPLEVEL": str(toplevel), **environment}):
            return self.sandboxes().checkout()

    def test_copy_colon_host_paths(self) -> None:
        """Explicit host paths containing colons work on either side of a copy."""
        self.paths.sandbox("c").joinpath("xfer").mkdir(parents=True)
        self.backend.add("c", expires=NOW + 60)
        directory = self.scratch / "tmp" / "logs:old"
        directory.mkdir()
        source = directory / "input.txt"
        source.write_text("report")
        sandboxes = self.sandboxes()
        self.assertEqual(sandboxes.copy(str(source), "c:/root/").target, "c:/root/")
        destination = directory / "output:report.txt"
        sandboxes.copy("c:/root/report.txt", str(destination))
        self.assertTrue(destination.is_file())
        with self.assertRaises(SbxError) as refused:
            sandboxes.copy("c:", str(destination))
        self.assertEqual(refused.exception.code, "invalid-argument")

    def test_checkout_root(self) -> None:
        """A toplevel counts only if it holds .git and neither is nor holds $HOME."""
        home = self.scratch / "home"
        repo = home / "repo"
        (repo / ".git").mkdir(parents=True)
        with mock.patch.dict(os.environ, {"HOME": str(home)}):
            self.assertEqual(self.checkout_root(repo), repo.resolve())
            self.assertEqual(self.checkout_root(repo, GIT_DIR="/elsewhere"), repo.resolve())
            # A repository with core.worktree=$HOME reports $HOME, which holds no .git.
            self.assertIsNone(self.checkout_root(home))
            (home / ".git").mkdir()
            self.assertIsNone(self.checkout_root(home))
            (self.scratch / ".git").mkdir()
            self.assertIsNone(self.checkout_root(self.scratch))
            with mock.patch.dict(os.environ, {"SBX_TEST_TOPLEVEL": str(home)}):
                self.assertNotIn(home.resolve(), self.sandboxes().host_roots())

    @unittest.skipUnless(os.environ.get("SBX_TEST_GIT"), "needs SBX_TEST_GIT")
    def test_checkout_root_core_worktree(self) -> None:
        """A repository whose core.worktree is $HOME adds no copy root."""
        git = os.environ["SBX_TEST_GIT"]
        self.settings = dataclasses.replace(
            self.settings, tools=dataclasses.replace(self.settings.tools, git=git)
        )
        home = self.scratch / "home"
        repo = home / "repo"
        repo.mkdir(parents=True)
        proc.run([git, "init", "-q", str(repo)])
        cwd = Path.cwd()
        self.addCleanup(os.chdir, cwd)
        os.chdir(repo)
        with mock.patch.dict(os.environ, {"HOME": str(home)}):
            self.assertEqual(self.sandboxes().checkout(), repo.resolve())
            proc.run([git, "config", "core.worktree", str(home)])
            self.assertIsNone(self.sandboxes().checkout())

    def add_running(self, name: str, *, expires: int = NOW + 60) -> None:
        """Register a running sandbox with its run directory."""
        (self.paths.sandbox(name) / "xfer").mkdir(parents=True)
        self.backend.add(name, expires=expires)

    def test_create_rechecks_ceilings(self) -> None:
        """A request built past the ceilings still fails at create."""
        request = model.Request("nixos", "t1", "none", 8192, 2, 3600)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(request)
        self.assertEqual(refused.exception.code, "over-limit")

    def test_disk_reservation(self) -> None:
        """Every running sandbox plus the new one reserves its full disk against the cap."""
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=15 << 30)
        self.add_running("r0")
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request())
        self.assertEqual(refused.exception.code, "disk-full")

    def test_nested_directory_links_refused(self) -> None:
        """A link to a directory inside the roots may lead out through a second link."""
        self.add_running("c")
        roots = self.scratch / "tmp"
        outside = self.scratch / "outside"
        outside.mkdir()
        (outside / "secret").write_text("s")
        first, second = roots / "a", roots / "b"
        first.mkdir()
        second.mkdir()
        (first / "link").symlink_to(second)
        (second / "evil").symlink_to(outside / "secret")
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().copy(str(first), "c:/root/")
        self.assertEqual(refused.exception.code, "path-denied")

    def test_copy_out_targets(self) -> None:
        """Copies out need a named leaf, never overwrite, and lose execute bits."""
        self.add_running("c")
        sandboxes = self.sandboxes()
        for guest in ("..", "/root/..", "/", "."):
            with self.subTest(guest=guest), self.assertRaises(SbxError):
                sandboxes.copy(f"c:{guest}", None)
        result = sandboxes.copy("c:/usr/bin/tool", None)
        copied = Path(str(result.target))
        self.assertEqual(copied, self.paths.sandbox("c") / "xfer" / "tool")
        self.assertEqual(copied.stat().st_mode & 0o7777, 0o644)
        with self.assertRaises(SbxError) as refused:
            sandboxes.copy("c:/usr/bin/tool", None)
        self.assertEqual(refused.exception.code, "exists")
        target = self.scratch / "tmp"
        self.assertEqual(
            sandboxes.copy("c:/usr/bin/tool", str(target)).target, str(target / "tool")
        )
        with self.assertRaises(SbxError):
            sandboxes.copy("c:/usr/bin/tool", str(target))
        self.assertEqual(list((self.paths.sandbox("c") / "xfer").glob(".stage-*")), [])

    def test_expired_sandboxes_refuse_access(self) -> None:
        """exec, cp, and screenshot refuse a sandbox past its TTL."""
        self.add_running("old", expires=NOW - 1)
        sandboxes = self.sandboxes()
        with self.assertRaises(SbxError) as refused:
            sandboxes.exec_capture("old", ["true"], ExecOptions())
        self.assertEqual(refused.exception.code, "expired")
        with self.assertRaises(SbxError):
            sandboxes.copy("old:/etc/hostname", None)
        with self.assertRaises(SbxError):
            sandboxes.screenshot("old", ocr=False)

    def test_screenshot_names(self) -> None:
        """Captures at one clock reading get their own files, even from parallel threads."""
        self.add_running("s")
        sandboxes = self.sandboxes()
        first = Path(sandboxes.screenshot("s", ocr=False).path)
        second = Path(sandboxes.screenshot("s", ocr=False).path)
        self.assertNotEqual(first, second)
        self.assertEqual((first.read_bytes(), second.read_bytes()), (b"png 1", b"png 2"))
        self.assertRegex(first.name, r"^screenshot-20270115T080000\.000000Z-[0-9a-f]{6}\.png$")
        mismatches: list[tuple[bytes, bytes]] = []

        def capture() -> None:
            path = Path(self.sandboxes().screenshot("s", ocr=False).path)
            own = self.backend.captured[threading.get_ident()]
            if path.read_bytes() != own:
                mismatches.append((path.read_bytes(), own))

        threads = [threading.Thread(target=capture) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(5)
        self.assertEqual(mismatches, [])
        xfer = self.paths.sandbox("s") / "xfer"
        self.assertEqual(len(list(xfer.glob("screenshot-*"))), 10)
        self.assertEqual(list(xfer.glob(".screenshot-*")), [])

    def test_screenshot_to(self) -> None:
        """--to takes a directory or a new file under the roots, checked before the capture."""
        self.add_running("s")
        tmp, outside = self.scratch / "tmp", self.scratch / "outside"
        outside.mkdir()
        (tmp / "taken.png").write_text("")
        result, _ = self.dispatch("--json", "screenshot", "s", "--to", str(tmp))
        saved = Path(str(cast("dict[str, object]", result)["path"]))
        self.assertEqual((saved.parent, saved.read_bytes()), (tmp, b"png 1"))
        result, _ = self.dispatch("--json", "screenshot", "s", "--to", str(tmp / "named.png"))
        self.assertEqual(cast("dict[str, object]", result)["path"], str(tmp / "named.png"))
        for target, code in ((tmp / "taken.png", "exists"), (outside, "path-denied")):
            with (
                self.subTest(target=target),
                mock.patch.object(self.backend, "screenshot") as capture,
                self.assertRaises(SbxError) as refused,
            ):
                self.dispatch("--json", "screenshot", "s", "--to", str(target))
            self.assertEqual(refused.exception.code, code)
            capture.assert_not_called()
        self.assertEqual(list((self.paths.sandbox("s") / "xfer").iterdir()), [])
        self.assertEqual((tmp / "taken.png").read_text(), "")

    def test_agent_replies_are_validated(self) -> None:
        """Malformed qemu-ga replies fail with agent-reply; good ones decode."""
        self.add_running("g")
        sandboxes = self.sandboxes()
        good = {"exited": True, "exitcode": 3, "out-data": "aGk=", "err-data": ""}
        self.backend.replies = [{"return": {"pid": 7}}, {"return": good}]
        result = sandboxes.exec_capture("g", ["x"], ExecOptions())
        self.assertEqual((result.exit_code, result.stdout), (3, b"hi"))
        malformed: list[list[dict[str, Any]]] = [
            [{"return": {"pid": "7"}}],
            [{"error": {}}],
            [{"return": {"pid": 7}}, {"return": {"exited": True, "out-data": "%%"}}],
            [{"return": {"pid": 7}}, {"return": {"exited": True}}],
        ]
        for replies in malformed:
            self.backend.replies = list(replies)
            with self.subTest(replies=replies), self.assertRaises(SbxError) as refused:
                sandboxes.exec_capture("g", ["x"], ExecOptions())
            self.assertEqual(refused.exception.code, "agent-reply")

    def test_foreign_domains_untouched(self) -> None:
        """A sbx-* domain without sbx metadata survives gc and destroy."""
        self.backend.domains_by_name["sbx-x"] = DomainInfo(
            name="sbx-x",
            state="running",
            active=True,
            memory_mib=1024,
            cpus=1,
            cid=5,
            meta=None,
            managed_save=False,
        )
        self.paths.sandbox("x").mkdir(parents=True)
        self.assertEqual(self.sandboxes().gc(dry_run=False), [GcAction("x", "no domain")])
        self.assertIn("sbx-x", self.backend.domains_by_name)
        self.paths.sandbox("x").mkdir()
        self.sandboxes().destroy("x")
        self.assertIn("sbx-x", self.backend.domains_by_name)

    def dispatch(self, *argv: str) -> tuple[object, int]:
        """Run one verb through the command line, in JSON mode."""
        return dispatch(self.sandboxes(), *argv)

    def assert_no_sandbox(self, name: str) -> None:
        """Neither a domain nor a run directory remains."""
        self.assertNotIn(f"sbx-{name}", self.backend.domains_by_name)
        self.assertFalse(self.paths.sandbox(name).exists())

    def test_copy_out_budget(self) -> None:
        """A copy out past the cap is cut off, and its stage removed."""
        self.add_running("c")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=4 << 20)
        xfer = self.paths.sandbox("c") / "xfer"
        for variable, value in (("SBX_TEST_BIG", str(16 << 20)), ("SBX_TEST_MANY", str(3 << 20))):
            with self.subTest(variable=variable), mock.patch.dict(os.environ, {variable: value}):
                with self.assertRaises(SbxError) as refused:
                    self.sandboxes().copy("c:/big", None)
                self.assertEqual(refused.exception.code, "disk-full")
                # Stopped during the transfer, not by the check after it.
                self.assertIn("budget", str(refused.exception))
                self.assertEqual(list(xfer.iterdir()), [])
                self.assertFalse((self.scratch / "scp.done").exists())

    def test_publish_never_replaces(self) -> None:
        """Two copies to one absent target: the second fails and the first stays."""
        target = self.scratch / "tmp" / "out"
        first, second = self.scratch / "first", self.scratch / "second"
        first.write_text("1")
        second.write_text("2")
        fsutil.publish(first, target)
        with self.assertRaises(SbxError) as refused:
            fsutil.publish(second, target)
        self.assertEqual(refused.exception.code, "exists")
        self.assertEqual(target.read_text(), "1")
        self.assertTrue(second.exists())

    def test_ssh_status_before_the_deadline(self) -> None:
        """An attached command's own exit 124 is no timeout, and an early ssh 255 is transport."""
        self.add_running("t")
        log = self.scratch / "ssh.log"
        for code in ("124", "255"):
            environment = {"SBX_TEST_SSH_EXIT": code, "SBX_TEST_SSH_LOG": str(log)}
            with self.subTest(code=code), mock.patch.dict(os.environ, environment):
                result = self.sandboxes().exec_attached("t", ["sleep", "9"], ExecOptions(timeout=2))
            self.assertFalse(result.timed_out)
            self.assertEqual(result.status(), int(code))
            self.assertEqual(result.transport_error is not None, code == "255")
            self.assertEqual(result.exit_code, 124 if code == "124" else None)
        remote = log.read_text().split("root@sbx\n--\n", 1)[1]
        self.assertTrue(remote.startswith("timeout --kill-after=5 2 /bin/sh -c "))

    def test_ssh_status_past_the_deadline(self) -> None:
        """Past the deadline, timeout's own statuses and ssh's 255 for its SIGKILL time out."""
        for code, signal in ((124, None), (137, "KILL"), (255, "KILL")):
            result = execution.ssh_result(code, 2.5, 2)
            self.assertEqual((result.timed_out, result.signal), (True, signal))
            self.assertEqual(result.status(), 124)
        self.assertEqual(execution.ssh_result(0, 2.5, 2).status(), 0)
        self.assertTrue(execution.ssh_result(None, 12, 2).timed_out)

    def test_agent_signal(self) -> None:
        """A command a signal ended has no exit code; its status is 128 plus the signal."""
        self.add_running("s")
        self.backend.replies = [{"return": {"pid": 7}}, {"return": {"exited": True, "signal": 9}}]
        result = self.sandboxes().exec_capture("s", ["x"], ExecOptions())
        document = result.as_json()
        self.assertEqual((document["exit_code"], document["signal"]), (None, "KILL"))
        self.assertFalse(document["timed_out"])
        self.assertEqual(result.status(), 137)

    def test_agent_deadline_kills_the_group(self) -> None:
        """Past the host deadline, SIGTERM then SIGKILL reach the group, and output is kept."""
        self.add_running("k")
        now = [0.0]
        stubborn = 7
        kills: list[str] = []

        def reply(_domain: str, command: dict[str, object], _timeout: int) -> dict[str, Any]:
            arguments = cast("dict[str, Any]", command["arguments"])
            if command["execute"] == "guest-exec":
                argv = [arguments["path"], *arguments["arg"]]
                if argv[1] == "-c" and argv[2].startswith("kill "):
                    kills.append(argv[2])
                    return {"return": {"pid": 50 + len(kills)}}
                return {"return": {"pid": stubborn}}
            if arguments["pid"] != stubborn:
                return {"return": {"exited": True, "exitcode": 0}}
            if any("KILL" in kill for kill in kills):
                partial = base64.b64encode(b"started\n").decode()
                return {"return": {"exited": True, "signal": 9, "out-data": partial}}
            now[0] += 0.5
            return {"return": {"exited": False}}

        sandboxes = self.sandboxes()
        sandboxes.monotonic = lambda: now[0]

        def pause(seconds: float) -> None:
            now[0] += seconds

        sandboxes.pause = pause
        with mock.patch.object(self.backend, "agent", reply):
            result = sandboxes.exec_capture("k", ["python3", "stubborn.py"], ExecOptions(timeout=1))
        self.assertEqual(
            kills,
            [
                "kill -TERM -7 2>/dev/null || kill -TERM 7",
                "kill -KILL -7 2>/dev/null || kill -KILL 7",
            ],
        )
        self.assertEqual((result.timed_out, result.killed, result.signal), (True, True, "KILL"))
        self.assertIsNone(result.exit_code)
        self.assertEqual(result.stdout, b"started\n")
        self.assertEqual(result.status(), 124)
        self.assertGreaterEqual(result.duration_s, 1 + agent.GUEST_KILL_AFTER)

    def test_agent_bad_signal(self) -> None:
        """A signal outside Linux's range is a malformed reply, never an exit status."""
        self.add_running("s")
        for number in (-1, 0, 65, 128):
            self.backend.replies = [
                {"return": {"pid": 7}},
                {"return": {"exited": True, "signal": number}},
            ]
            with self.subTest(number=number), self.assertRaises(SbxError) as refused:
                self.sandboxes().exec_capture("s", ["x"], ExecOptions())
            self.assertEqual(refused.exception.code, "agent-reply")

    def test_agent_kill_refused(self) -> None:
        """A kill qemu-ga refuses to start still leads to SIGKILL, and the result timed out."""
        now = [0.0]
        kills: list[str] = []

        def call(execute: str, arguments: dict[str, object]) -> object:
            if execute == "guest-exec":
                argv = cast("list[str]", arguments["arg"])
                if argv[:1] == ["-c"]:
                    kills.append(argv[1])
                    msg = "guest-exec refused"
                    raise SbxError(msg, code="libvirt")
                return {"pid": 7}
            now[0] += 0.5
            return {"exited": False}

        def pause(seconds: float) -> None:
            now[0] += seconds

        guest = agent.GuestExec(call, clock=lambda: now[0], pause=pause)
        result = guest.run("x", [], timeout=1, limit=1024, stops=guest.group_stops())
        self.assertEqual([kill.split()[1] for kill in kills], ["-TERM", "-KILL"])
        self.assertEqual((result.timed_out, result.transport_error), (True, None))
        self.assertIn(b"may still run: qemu-ga: guest-exec refused", result.stderr)
        self.assertEqual(result.status(), 124)

    def test_agent_kill_before_setsid(self) -> None:
        """A kill before the launcher's setsid, with no process group yet, signals the pid."""
        scripts: list[list[str]] = []

        def call(execute: str, arguments: dict[str, object]) -> object:
            if execute == "guest-exec":
                scripts.append([str(arguments["path"]), *cast("list[str]", arguments["arg"])])
                return {"pid": 1}
            return {"exited": True, "exitcode": 0}

        guest = agent.GuestExec(call)
        # A child of this process, so no process group carries its pid.
        with subprocess.Popen(["sleep", "30"]) as process:
            self.assertIsNone(guest.group_stops()[0].send(process.pid))
            subprocess.run(scripts[0], check=True)
            self.assertEqual(process.wait(5), -15)

    def test_launcher_profile_sees_the_user(self) -> None:
        """The profile runs once HOME, USER, and LOGNAME name the target user."""
        home = self.scratch / "home"
        home.mkdir()
        stubs = self.scratch / "launcher-stubs"
        stubs.mkdir()
        getent = stubs / "getent"
        getent.write_text(f'#!/bin/sh\necho "alice:x:0:0::{home}:/bin/sh"\n')
        getent.chmod(0o755)
        profile = self.scratch / "profile"
        seen = self.scratch / "seen"
        profile.write_text(f'echo "$USER $LOGNAME $HOME" > {seen}\n')
        script = execution.LAUNCH.replace("/etc/profile", str(profile))
        argv = execution.launcher(["true"], ExecOptions(user="alice"), session=False)
        environment = {"PATH": f"{stubs}:{os.environ['PATH']}"}
        subprocess.run([*argv[:2], script, *argv[3:]], check=True, env=environment)
        self.assertEqual(seen.read_text(), f"alice alice {home}\n")

    def test_agent_transport_error(self) -> None:
        """A guest agent lost after the start is a transport error, never a guest status."""
        self.add_running("x")
        self.backend.replies = [{"return": {"pid": 7}}]
        lost = SbxError("agent gone", code="libvirt")
        ping = self.backend.agent

        def reply(domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:
            if command["execute"] == "guest-exec-status":
                raise lost
            return ping(domain, command, timeout)

        with mock.patch.object(self.backend, "agent", reply):
            result = self.sandboxes().exec_capture("x", ["true"], ExecOptions())
        self.assertEqual(result.transport_error, "qemu-ga: agent gone")
        self.assertEqual(result.status(), 255)

    def test_json_exit_codes(self) -> None:
        """The guest's status is the exit status of exec --json, which runs through qemu-ga."""
        self.add_running("j")
        self.backend.exit_status = {"exitcode": 3}
        result, code = self.dispatch("--json", "exec", "j", "--", "false")
        self.assertEqual(code, 3)
        self.assertEqual(cast("dict[str, object]", result)["exit_code"], 3)
        argv, _stdin = self.backend.execs[-1]
        self.assertEqual(argv, execution.launcher(["false"], ExecOptions(), session=True))

    def test_zero_timeout(self) -> None:
        """--timeout 0s is refused before anything runs, as the MCP tools refuse it too."""
        self.add_running("z")
        with self.assertRaises(SbxError) as refused:
            self.dispatch("--json", "exec", "z", "--timeout", "0s", "--", "true")
        self.assertEqual(refused.exception.code, "invalid-argument")
        self.assertEqual(self.backend.execs, [])

    def test_output_encoding(self) -> None:
        """Text output flags replaced bytes; base64 output carries them exactly."""
        self.add_running("b")
        raw = b"\xff\xfe\x00ok"
        self.backend.exit_status = {
            "exitcode": 0,
            "out-data": base64.b64encode(raw).decode(),
            "err-data": base64.b64encode("é".encode()).decode(),
        }
        text = cast("dict[str, object]", self.dispatch("--json", "exec", "b", "--", "x")[0])
        self.assertEqual((text["stdout_lossy"], text["stderr_lossy"]), (True, False))
        self.assertEqual((text["stdout"], text["stderr"]), ("\ufffd\ufffd\x00ok", "é"))
        argv = ("--json", "exec", "b", "--output-encoding", "base64", "--", "x")
        encoded = cast("dict[str, object]", self.dispatch(*argv)[0])
        self.assertEqual(base64.b64decode(cast("str", encoded["stdout"])), raw)
        self.assertEqual(base64.b64decode(cast("str", encoded["stderr"])), "é".encode())
        self.assertEqual((encoded["stdout_lossy"], encoded["stderr_lossy"]), (False, False))

    def test_launcher(self) -> None:
        """Both transports run one launcher: root in its home by default, else as asked."""
        options = ExecOptions(cwd="/srv", env=("A=1", "B=x y"), user="sbx")
        argv = execution.launcher(["id", "-u"], options, session=True)
        self.assertEqual(argv[:4], ["/bin/sh", "-c", execution.LAUNCH, "sbx"])
        self.assertEqual(argv[4:], ["sbx", "/srv", "setsid", "A=1", "B=x y", "--", "id", "-u"])
        argv = execution.launcher(["id"], ExecOptions(), session=False)
        self.assertEqual(argv[4:], ["root", "", "", "--", "id"])
        syntax = subprocess.run(["/bin/sh", "-n", "-c", execution.LAUNCH], check=False)
        self.assertEqual(syntax.returncode, 0)
        self.add_running("l")
        log = self.scratch / "ssh.log"
        with mock.patch.dict(os.environ, {"SBX_TEST_SSH_LOG": str(log)}):
            self.sandboxes().exec_attached("l", ["pwd"], ExecOptions(cwd="/srv"))
        remote = log.read_text().split("root@sbx\n--\n", 1)[1].removesuffix("\n")
        self.assertEqual(
            remote, shlex.join(execution.launcher(["pwd"], ExecOptions(cwd="/srv"), session=False))
        )

    def test_exec_option_validation(self) -> None:
        """--env needs NAME=VALUE without NUL, --cwd an absolute path, stdin at most 1 MiB."""
        cases: list[dict[str, Any]] = [
            {"env": ["NOEQUALS"]},
            {"env": ["1A=x"]},
            {"env": ["A=x\0y"]},
            {"env": ["=x"]},
            {"cwd": "relative"},
            {"cwd": "/a\0b"},
            {"user": "-root"},
            {"stdin": b"x" * (execution.MAX_STDIN + 1)},
        ]
        for options in cases:
            with self.subTest(options=options), self.assertRaises(SbxError) as refused:
                execution.exec_options(**options)
            self.assertEqual(refused.exception.code, "invalid-argument")
        accepted = execution.exec_options(env=["A=", "B=c=d"], cwd="/", user="sbx", stdin=b"")
        self.assertEqual(accepted.env, ("A=", "B=c=d"))

    def test_stdin(self) -> None:
        """--stdin goes to qemu-ga as base64 input-data; more than 1 MiB is refused unsent."""
        self.add_running("i")
        data = bytes(range(256))
        source = self.scratch / "tmp" / "input"
        source.write_bytes(data)
        self.dispatch("--json", "exec", "i", "--stdin", str(source), "--", "cat")
        argv, stdin = self.backend.execs[-1]
        self.assertEqual((argv[-1], stdin), ("cat", data))
        source.write_bytes(b"x" * (execution.MAX_STDIN + 1))
        sent = len(self.backend.execs)
        with self.assertRaises(SbxError) as refused:
            self.dispatch("--json", "exec", "i", "--stdin", str(source), "--", "cat")
        self.assertEqual(refused.exception.code, "invalid-argument")
        self.assertEqual(len(self.backend.execs), sent)
        outside = self.scratch / "outside"
        outside.write_bytes(b"secret")
        with self.assertRaises(SbxError) as refused:
            self.dispatch("--json", "exec", "i", "--stdin", str(outside), "--", "cat")
        self.assertEqual(refused.exception.code, "path-denied")

    def test_exec_flags(self) -> None:
        """--cwd, repeated --env, and --user reach the launcher."""
        self.add_running("f")
        self.dispatch(
            "--json",
            "exec",
            "f",
            "--cwd",
            "/work",
            "--env",
            "A=1",
            "--env",
            "B=2",
            "--user",
            "sbx",
            "--",
            "env",
        )
        argv, _stdin = self.backend.execs[-1]
        self.assertEqual(argv[4:], ["sbx", "/work", "setsid", "A=1", "B=2", "--", "env"])

    def test_run_refusals_before_create(self) -> None:
        """Bad flags, host paths, and output leaves refuse before anything boots or queues."""
        tmp, outside = self.scratch / "tmp", self.scratch / "outside"
        outside.mkdir()
        for directory in ("a", "b"):
            (tmp / directory).mkdir()
            (tmp / directory / "f").write_text(directory)
        (tmp / "taken").write_text("")
        to = ("--to", str(tmp))
        cases: list[tuple[tuple[str, ...], str]] = [
            (("--out", "/x"), "usage"),
            (("--to", "."), "usage"),
            (("--timeout", "5x"), "invalid-argument"),
            (("--timeout", "0s"), "invalid-argument"),
            (("--in", str(tmp / "missing")), "os-error"),
            (("--in", str(outside)), "path-denied"),
            (("--in", str(tmp / "a" / "f"), "--in", str(tmp / "b" / "f")), "invalid-argument"),
            (("--out", "/root/x", "--to", str(outside)), "path-denied"),
            (("--out", "/", *to), "invalid-argument"),
            (("--out", "/root/..", *to), "invalid-argument"),
            (("--out", "/root/a/x", "--out", "/root/b/x", *to), "invalid-argument"),
            (("--out", "/root/taken", *to), "exists"),
            (("--wait", "10m", "--in", str(outside)), "path-denied"),
        ]
        for flags, code in cases:
            argv = ("run", "nixos", "--name", "r", *flags, "--", "true")
            with (
                self.subTest(flags=flags),
                mock.patch.object(self.backend, "start") as start,
                self.assertRaises((SbxError, OSError)) as refused,
            ):
                self.dispatch(*argv)
            failure = refused.exception
            self.assertEqual(failure.code if isinstance(failure, SbxError) else "os-error", code)
            start.assert_not_called()
            self.assert_no_sandbox("r")
        self.assertFalse(self.paths.queue.exists() and any(self.paths.queue.iterdir()))

    def run_incomplete(self, *argv: str) -> tuple[str, dict[str, Any]]:
        """Run a run that fails after create; return its failed phase and result document."""
        with self.assertRaises(SbxError) as refused:
            self.dispatch("--json", "run", "nixos", "--name", "r", *argv)
        error = refused.exception
        self.assertEqual(error.code, "run-incomplete")
        document = errors.error_document(error)
        self.assertEqual(document["run"], error.details["run"])
        return str(document["phase"]), cast("dict[str, Any]", document["run"])

    def test_run_destroys_on_failure(self) -> None:
        """A failed copy in or exec skips the later steps and still destroys the run sandbox."""
        tmp = self.scratch / "tmp"
        (tmp / "input").write_text("")
        failure = SbxError("boom", code="test")
        with mock.patch.object(Sandboxes, "copy", side_effect=failure):
            phase, run = self.run_incomplete("--in", str(tmp / "input"), "--", "true")
        self.assertEqual((phase, run["failure"]["code"]), ("in", "test"))
        self.assertEqual((run["phases"]["exec"], run["exec"]), ("skipped", None))
        self.assert_no_sandbox("r")
        with mock.patch.object(Sandboxes, "exec_capture", side_effect=failure):
            phase, run = self.run_incomplete("--out", "/root/x", "--to", str(tmp), "--", "true")
        self.assertEqual((phase, run["failure"]["code"]), ("exec", "test"))
        self.assertEqual((run["phases"]["out"], run["out"]), ("skipped", []))
        self.assertEqual(run["cleanup"], {"destroyed": ["r"], "error": None})
        self.assert_no_sandbox("r")

    def test_run_keeps_the_result_of_a_failed_export(self) -> None:
        """A failed copy out keeps the command's result, and the other outputs still publish."""
        self.backend.exit_status = {"exitcode": 7}
        target = self.scratch / "tmp"
        phase, run = self.run_incomplete(
            "--out", "/root/missing.json", "--out", "/root/report.txt", "--to", str(target),
            "--", "sh", "-c", "exit 7",
        )  # fmt: skip
        self.assertEqual(phase, "out")
        self.assertEqual(run["exec"]["exit_code"], 7)
        self.assertEqual(run["phases"], dict.fromkeys(pipeline.PHASES, "ok") | {"out": "failed"})
        failed, published = run["out"]
        self.assertEqual(failed["from"], "r:/root/missing.json")
        self.assertEqual(failed["error"]["code"], "command-failed")
        self.assertEqual(published["to"], str(target / "report.txt"))
        self.assertTrue((target / "report.txt").is_file())
        self.assertEqual(run["cleanup"], {"destroyed": ["r"], "error": None})
        self.assert_no_sandbox("r")

    def test_run_cleanup_failure(self) -> None:
        """A failed destroy lands in cleanup.error without masking the command's result."""
        failure = SbxError("daemon gone", code="libvirt")
        with mock.patch.object(Sandboxes, "destroy_created", side_effect=failure):
            phase, run = self.run_incomplete("--", "true")
        self.assertEqual(phase, "cleanup")
        self.assertEqual(run["exec"]["exit_code"], 0)
        self.assertEqual(run["cleanup"]["destroyed"], [])
        self.assertEqual(run["cleanup"]["error"]["code"], "libvirt")
        self.assertIsNone(run["failure"])

    def test_run_document(self) -> None:
        """A complete run reports creation metadata only, every phase, and its cleanup."""
        result, code = self.dispatch("--json", "run", "nixos", "--name", "r", "--", "true")
        document = cast("dict[str, Any]", result)
        self.assertEqual(code, 0)
        self.assertEqual(tuple(document["sandbox"]), pipeline.SANDBOX_FIELDS)
        self.assertEqual(document["phases"], dict.fromkeys(pipeline.PHASES, "ok"))
        self.assertEqual(document["cleanup"], {"destroyed": ["r"], "error": None})
        self.assertIsNone(document["failure"])
        self.assertEqual(document["exec"]["exit_code"], 0)
        self.assert_no_sandbox("r")

    def egress(self, flags: str = "0x1003") -> Path:
        """Configure vn-sbx with a fake sysfs entry and return its lease file."""
        sys_net = self.scratch / "sys-net"
        (sys_net / "vn-sbx" / "bridge").mkdir(parents=True)
        (sys_net / "vn-sbx" / "flags").write_text(f"{flags}\n")
        patch = mock.patch.object(admission, "SYS_NET", sys_net)
        patch.start()
        self.addCleanup(patch.stop)
        leases = self.scratch / "vn-sbx.status"
        self.settings = dataclasses.replace(self.settings, egress=Egress("vn-sbx", leases, 1240))
        mac = mock.patch.object(lifecycle, "random_mac", return_value=MAC)
        mac.start()
        self.addCleanup(mac.stop)
        return leases

    def test_egress_unavailable(self) -> None:
        """Egress is refused without a usable network, a bridge, or an up bridge."""
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request(net="egress"))
        self.assertEqual(refused.exception.code, "egress-unavailable")
        self.assertEqual(str(refused.exception), "no egress network")
        self.egress(flags="0x1002")
        device = admission.SYS_NET / "vn-sbx"
        for case in ("down", "flags vanished", "absent"):
            if case == "flags vanished":
                (device / "flags").unlink()
            if case == "absent":
                (device / "bridge").rmdir()
            with self.subTest(case=case), self.assertRaises(SbxError) as refused:
                self.sandboxes().create(self.request(net="egress"))
            self.assertEqual(refused.exception.code, "egress-unavailable")
            self.assert_no_sandbox("t1")

    def test_egress_create(self) -> None:
        """An egress sandbox gets one virtio NIC on the bridge and reports its leased address."""
        leases = self.egress()
        leases.write_text(
            json.dumps(
                [
                    {"ip-address": "172.16.2.9", "mac-address": MAC, "expiry-time": NOW - 1},
                    {
                        "ip-address": "172.16.2.7",
                        "mac-address": "52:54:00:00:00:01",
                        "expiry-time": NOW + 60,
                    },
                    {
                        "ip-address": "172.16.2.5",
                        "mac-address": MAC.upper(),
                        "expiry-time": NOW + 3600,
                    },
                ]
            )
        )
        result = self.sandboxes().create(self.request(net="egress"))
        self.assertEqual((result.net, result.address), ("egress", "172.16.2.5"))
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        interfaces = root.findall("devices/interface")
        self.assertEqual(len(interfaces), 1)
        interface = interfaces[0]
        self.assertEqual(interface.get("type"), "bridge")
        self.assertEqual(interface.find("source").get("bridge"), "vn-sbx")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(interface.find("model").get("type"), "virtio")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(interface.find("mac").get("address"), MAC)  # pyright: ignore[reportOptionalMemberAccess]
        listed = Results(self.sandboxes().listing(mine=False)).as_json()
        self.assertEqual(
            [cast("dict[str, object]", entry)["address"] for entry in listed], ["172.16.2.5"]
        )
        self.assertEqual(self.sandboxes().info("t1").address, "172.16.2.5")

    def test_egress_without_lease(self) -> None:
        """A guest that never takes a lease fails create with no-address and is discarded."""
        self.egress().write_text("")
        # The boot deadline runs on the monotonic clock.
        ticks = itertools.count(0, 2)
        with (
            mock.patch.object(lifecycle.time, "sleep"),
            mock.patch.object(lifecycle.time, "monotonic", side_effect=ticks),
            self.assertRaises(SbxError) as refused,
        ):
            self.sandboxes(None).create(self.request(net="egress"))
        self.assertEqual(refused.exception.code, "no-address")
        self.assert_no_sandbox("t1")

    def test_egress_waits_for_guest_address(self) -> None:
        """Create waits past the lease until the guest's NIC carries it, else fails no-address."""
        self.egress().write_text(
            json.dumps([{"ip-address": "172.16.2.5", "mac-address": MAC, "expiry-time": 0}])
        )
        self.backend.addresses = []

        def configure(_seconds: float) -> None:
            self.backend.addresses = ["172.16.2.5"]

        with mock.patch.object(lifecycle.time, "sleep", side_effect=configure):
            result = self.sandboxes().create(self.request(net="egress"))
        self.assertEqual(result.address, "172.16.2.5")
        self.backend.addresses = ["172.16.2.6"]
        ticks = iter(range(0, 10_000, 2))
        with (
            mock.patch.object(lifecycle.time, "sleep"),
            mock.patch.object(lifecycle.time, "monotonic", side_effect=lambda: next(ticks)),
            self.assertRaises(SbxError) as refused,
        ):
            self.sandboxes().create(self.request(name="t2", net="egress"))
        self.assertEqual(refused.exception.code, "no-address")
        self.assert_no_sandbox("t2")

    def test_guest_interfaces(self) -> None:
        """The NIC is matched by MAC, other NICs' addresses do not count, bad replies fail."""
        nic = {"hardware-address": MAC, "ip-addresses": [{"ip-address": "172.16.2.5"}]}
        self.assertTrue(
            agent.guest_holds({"return": [{"name": "lo"}, nic]}, MAC.upper(), "172.16.2.5")
        )
        self.assertFalse(agent.guest_holds({"return": [nic]}, "52:54:00:00:00:01", "172.16.2.5"))
        self.assertFalse(
            agent.guest_holds({"return": [{"hardware-address": MAC}]}, MAC, "172.16.2.5")
        )
        bad: list[dict[str, Any]] = [
            {},
            {"return": {}},
            {"return": [1]},
            {"return": [nic | {"ip-addresses": 1}]},
        ]
        for reply in bad:
            with self.subTest(reply=reply), self.assertRaises(SbxError) as refused:
                agent.guest_holds(reply, MAC, "172.16.2.5")
            self.assertEqual(refused.exception.code, "agent-reply")

    def test_lease_file(self) -> None:
        """Missing and empty files hold no lease, malformed ones fail, IPv6 is skipped."""
        path = self.scratch / "leases"
        self.assertIsNone(net.lease_address(path, MAC, NOW))
        path.write_text("")
        self.assertIsNone(net.lease_address(path, MAC, NOW))
        entries = [
            {"ip-address": "fd00::5", "mac-address": MAC, "expiry-time": NOW + 60},
            {"ip-address": "172.16.2.3", "mac-address": MAC, "expiry-time": 0},
        ]
        path.write_text(json.dumps(entries))
        self.assertEqual(net.lease_address(path, MAC.upper(), NOW), "172.16.2.3")
        for text in ("{", "{}", "[1]", '[{"ip-address": "172.16.2.3"}]'):
            path.write_text(text)
            with self.subTest(text=text), self.assertRaises(SbxError) as refused:
                net.lease_address(path, MAC, NOW)
            self.assertEqual(refused.exception.code, "lease-file")

    def test_malformed_leases(self) -> None:
        """A bad lease file leaves the address out of a listing but fails create."""
        leases = self.egress()
        leases.write_text(
            json.dumps([{"ip-address": "172.16.2.5", "mac-address": MAC, "expiry-time": 0}])
        )
        self.sandboxes().create(self.request(net="egress"))
        leases.write_text("{")
        listed = Results(self.sandboxes().listing(mine=False)).as_json()
        self.assertEqual([cast("dict[str, object]", entry)["address"] for entry in listed], [None])
        self.assertIsNone(self.sandboxes().info("t1").address)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request(name="t2", net="egress"))
        self.assertEqual(refused.exception.code, "lease-file")
        self.assert_no_sandbox("t2")

    def test_none_has_no_address(self) -> None:
        """A sandbox without a NIC reports no address even with egress configured."""
        self.egress()
        result = self.sandboxes().create(self.request())
        self.assertIsNone(result.address)
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        self.assertIsNone(root.find("devices/interface"))

    def test_settings_egress(self) -> None:
        """The rendered settings carry the egress bridge, or why there is none."""
        raw: dict[str, object] = {
            "limits": {
                "running": 3,
                "memoryMiB": 1,
                "sandboxMemoryMiB": 1,
                "sandboxCpus": 1,
                "ttlSeconds": 1,
                "diskBytes": 1,
                "minFreeBytes": 1,
                "fileBytes": 1,
            },
            "defaults": {
                "memoryMiB": 1,
                "guiMemoryMiB": 2,
                "cpus": 1,
                "ttlSeconds": 1,
                "diskGiB": 1,
            },
            "cpuset": "0",
            "flake": "/flake",
            "unit": "u",
            "slice": "s",
            "outputLimit": 1,
            "bootTimeout": 1,
            "egress": {"bridge": "vn-sbx", "leases": "/leases", "mtu": 1240},
            "cloudImages": {"debian-13": {"url": "https://x/d.qcow2", "hash": "sha256-y"}},
            "windows": None,
            "tools": dataclasses.asdict(self.settings.tools),
        }
        path = self.scratch / "settings.json"
        path.write_text(json.dumps(raw))
        loaded = Settings.load(path)
        self.assertEqual(loaded.egress, Egress("vn-sbx", Path("/leases"), 1240))
        self.assertEqual(
            loaded.cloud_images, {"debian-13": CloudImage("https://x/d.qcow2", "sha256-y")}
        )
        self.assertEqual(loaded.default_gui_memory_mib, 2)
        path.write_text(json.dumps(raw | {"egress": "why"}))
        self.assertEqual(Settings.load(path).egress, "why")

    def test_gui_request(self) -> None:
        """--gui picks the GUI variant with its own default memory; bases without one refuse."""
        request = self.request(gui=True)
        self.assertEqual((request.base, request.memory_mib), ("nixos-gui", 4096))
        request = self.request("nixos-gui")
        self.assertEqual((request.base, request.memory_mib), ("nixos-gui", 4096))
        self.assertEqual(self.request(memory="1G", gui=True).memory_mib, 1024)
        with self.assertRaises(SbxError) as refused:
            self.request("debian-13", gui=True)
        self.assertEqual(refused.exception.code, "unknown-base")

    def test_gui_domain(self) -> None:
        """A GUI sandbox gets a SPICE socket without clipboard, file transfer, or vdagent."""
        self.sandboxes().create(self.request(gui=True))
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        graphics = root.findall("devices/graphics")
        self.assertEqual([element.get("type") for element in graphics], ["spice"])
        self.assertEqual(graphics[0].find("listen").get("type"), "socket")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(graphics[0].find("clipboard").get("copypaste"), "no")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(graphics[0].find("filetransfer").get("enable"), "no")  # pyright: ignore[reportOptionalMemberAccess]
        channels = [target.get("name") for target in root.iterfind("devices/channel/target")]
        self.assertEqual(channels, ["org.qemu.guest_agent.0"])

    def test_key_and_type(self) -> None:
        """Chords reach the display as Linux keycodes; text goes to xdotool in the session."""
        self.sandboxes().create(self.request(gui=True))
        text = "H\u00e9 \u2713!\n"
        with (
            mock.patch.object(gui.time, "sleep"),
            mock.patch.object(self.backend, "agent", wraps=self.backend.agent) as agent_call,
        ):
            result, _ = self.dispatch("key", "t1", "ctrl+alt+t", "Return")
            self.assertEqual(result, {"sandbox": "t1", "keys": ["ctrl+alt+t", "Return"]})
            result, _ = self.dispatch("type", "t1", text)
            self.assertEqual(result, {"sandbox": "t1", "characters": len(text)})
        self.assertEqual([codes for _domain, codes in self.backend.keys], [[29, 56, 20], [28]])
        self.assertEqual({domain for domain, _codes in self.backend.keys}, {"sbx-t1"})
        (started,) = [
            call.args[1]["arguments"]
            for call in agent_call.call_args_list
            if call.args[1]["execute"] == "guest-exec"
        ]
        self.assertEqual(started["input-data"], base64.b64encode(text.encode()).decode())
        (argv, stdin) = self.backend.execs[-1]
        self.assertEqual(stdin, text.encode())
        self.assertEqual(argv[4:8], ["sbx", "", "setsid", "DISPLAY=:0"])
        self.assertEqual(argv[8:], ["--", "xdotool", "type", "--clearmodifiers", "--file", "-"])
        self.assert_text_unlogged(text, "type in t1: 6 characters")

    def assert_text_unlogged(self, text: str, line: str) -> None:
        """The journal names the text's length and nothing of the text."""
        records = cast("mock.Mock", gui.journal.record).call_args_list
        logged = [call.args[0] for call in records]
        self.assertIn(line, logged)
        for call in records:
            fields = [*map(str, call.args), *map(str, call.kwargs.values())]
            self.assertFalse([field for field in fields if text.strip() in field], call)

    def test_type_keys_mode(self) -> None:
        """Keycode typing turns a lit Caps Lock off around the text and back on after it."""
        self.sandboxes().create(self.request(gui=True))
        lit = {"exitcode": 0, "out-data": base64.b64encode(b"1\n0\n").decode()}
        for led, expected in (
            (lit, [[58], [42, 35], [23], [58]]),
            ({"exitcode": 0, "out-data": base64.b64encode(b"0\n").decode()}, [[42, 35], [23]]),
        ):
            self.backend.keys.clear()
            self.backend.exit_status = led
            with self.subTest(led=led), mock.patch.object(gui.time, "sleep"):
                result, _ = self.dispatch("type", "t1", "--mode", "keys", "Hi")
                self.assertEqual(result, {"sandbox": "t1", "characters": 2})
                self.assertEqual([codes for _domain, codes in self.backend.keys], expected)
                argv, stdin = self.backend.execs[-1]
                self.assertEqual((argv, stdin), (["/bin/sh", "-c", gui.CAPS_LED], b""))
        self.assert_text_unlogged("Hi", "type in t1: 2 characters")
        self.backend.keys.clear()
        for reply in (
            {"exitcode": 0, "out-data": base64.b64encode(b"on").decode()},
            {"exitcode": 0},
            {"exitcode": 1},
        ):
            self.backend.exit_status = reply
            with self.subTest(reply=reply), self.assertRaises(SbxError) as refused:
                self.dispatch("type", "t1", "--mode", "keys", "Hi")
            self.assertIn(refused.exception.code, {"agent-reply", "guest-command"})
        self.assertEqual(self.backend.keys, [])

    def test_type_failure(self) -> None:
        """A failing xdotool is a guest-command error that quotes its stderr, not the text."""
        self.sandboxes().create(self.request(gui=True))
        stderr = base64.b64encode(b"Can't open display: :0\n").decode()
        self.backend.exit_status = {"exitcode": 1, "err-data": stderr}
        with self.assertRaises(SbxError) as failed:
            self.dispatch("type", "t1", "secret")
        self.assertEqual(failed.exception.code, "guest-command")
        self.assertIn("Can't open display", str(failed.exception))
        self.assertNotIn("secret", str(failed.exception))

    def test_input_refusals(self) -> None:
        """Unknown keys, untypable text, and sandboxes without a display send nothing."""
        self.sandboxes().create(self.request(gui=True))
        self.add_running("plain")
        self.backend.add("old", expires=NOW - 1, base="nixos-gui")
        cases = [
            (("key", "t1", "ctrl+nope"), "invalid-argument"),
            (("key", "t1", "+".join(["a"] * 17)), "invalid-argument"),
            (("type", "t1", "--mode", "keys", "x\u00e9"), "invalid-argument"),
            (("type", "t1", "a\rb"), "invalid-argument"),
            (("type", "t1", "a\x00b"), "invalid-argument"),
            (("type", "t1", "a\ud800"), "invalid-argument"),
            (("type", "t1", "--mode", "keys", "a\rb"), "invalid-argument"),
            (("type", "t1", "x" * (gui.TYPE_LIMIT + 1)), "invalid-argument"),
            (("type", "t1", "--mode", "mouse", "x"), "usage"),
            (("key", "plain", "enter"), "no-display"),
            (("type", "plain", "x"), "no-display"),
            (("type", "plain", "--mode", "keys", "x"), "no-display"),
            (("key", "old", "enter"), "expired"),
        ]
        for argv, code in cases:
            with self.subTest(argv=argv), self.assertRaises(SbxError) as refused:
                self.dispatch(*argv)
            self.assertEqual(refused.exception.code, code)
        self.assertEqual(self.backend.keys, [])
        self.assertEqual(self.backend.execs, [])
        with self.assertRaises(SbxError) as refused:
            self.dispatch("type", "t1", "--mode", "keys", "\u2713")
        self.assertIn("default mode", str(refused.exception))

    def test_type_failures_keep_the_text_out(self) -> None:
        """No refusal or guest failure of type names a typed character, in its error or journal."""
        self.sandboxes().create(self.request(gui=True))
        echoed = base64.b64encode("I don't know which key produces '\u00e4', skipping.\n".encode())
        cases = [
            ((), {"exitcode": 0}, "\u00e4\x07\u00f6", "invalid-argument"),
            (("--mode", "keys"), {"exitcode": 0}, "\u00e4b\u00f6", "invalid-argument"),
            ((), {"exitcode": 1, "err-data": echoed.decode()}, "\u00e4\u00f6", "guest-command"),
            ((), {"exitcode": 0, "err-data": echoed.decode()}, "\u00e4\u00f6", "guest-command"),
        ]
        records = cast("mock.Mock", gui.journal.record)
        for flags, status, text, code in cases:
            self.backend.exit_status = status
            records.reset_mock()
            with self.subTest(text=text, status=status), self.assertRaises(SbxError) as failed:
                self.dispatch("type", "t1", *flags, text)
            self.assertEqual(failed.exception.code, code)
            fields = [str(failed.exception)]
            for call in records.call_args_list:
                fields += [*map(str, call.args), *map(str, call.kwargs.values())]
            self.assertIn(f"failed: {failed.exception}", fields)
            for character in ("\u00e4", "\u00f6", "\x07"):
                self.assertFalse([field for field in fields if character in field], text)
        self.assertEqual(self.backend.keys, [])

    def test_key_cap(self) -> None:
        """The key verb presses at most MAX_CHORDS chords and refuses more before sending any."""
        self.sandboxes().create(self.request(gui=True))
        with mock.patch.object(gui.time, "sleep"):
            self.dispatch("key", "t1", *["a"] * keys.MAX_CHORDS)
        self.assertEqual(len(self.backend.keys), keys.MAX_CHORDS)
        self.backend.keys.clear()
        with self.assertRaises(SbxError) as refused:
            self.dispatch("key", "t1", *["a"] * (keys.MAX_CHORDS + 1))
        self.assertEqual(refused.exception.code, "invalid-argument")
        self.assertEqual(self.backend.keys, [])

    def guest_prints(self, stdout: bytes, code: int = 0) -> None:
        """Make every guest command exit with this status and stdout."""
        self.backend.exit_status = {"exitcode": code, "out-data": base64.b64encode(stdout).decode()}

    def guest_script(self) -> list[str]:
        """Return the last guest command after the launcher, checking it ran as sbx on :0."""
        argv, _stdin = self.backend.execs[-1]
        self.assertEqual(argv[4:9], ["sbx", "", "setsid", "DISPLAY=:0", "--"])
        return argv[9:]

    def test_mouse(self) -> None:
        """The pointer moves through xdotool in the session; a double click defaults to left."""
        self.sandboxes().create(self.request(gui=True))
        cases = [
            (("--to", "100,200"), ["100", "200", "", "1"], None, False),
            (("--to", "0,0", "--click", "right"), ["0", "0", "3", "1"], "right", False),
            (("--to", "5,6", "--double"), ["5", "6", "1", "2"], "left", True),
        ]
        for flags, args, click, double in cases:
            with self.subTest(flags=flags):
                result, _ = self.dispatch("mouse", "t1", *flags)
                x, y = map(int, flags[1].split(","))
                self.assertEqual(
                    result, {"sandbox": "t1", "x": x, "y": y, "click": click, "double": double}
                )
                self.assertEqual(self.guest_script(), ["/bin/sh", "-c", gui.MOUSE, "sbx", *args])
        self.assertEqual(self.backend.keys, [])

    def test_windows(self) -> None:
        """Window verbs run their scripts in the session and read the guest's lines strictly."""
        self.sandboxes().create(self.request(gui=True))
        name = base64.b64encode("sbx@sbx: ~ \u2713\n".encode())
        line = b"4194 WINDOW=4194 X=0 Y=-2 WIDTH=484 HEIGHT=316 SCREEN=0 " + name
        xterm = {
            "id": 4194,
            "name": "sbx@sbx: ~ \u2713",
            "geometry": {"x": 0, "y": -2, "width": 484, "height": 316},
        }
        self.guest_prints(b"ready\n" + line + b"\n")
        result, _ = self.dispatch("window", "wait", "t1", "--class", "^xterm$")
        self.assertEqual(result, {"sandbox": "t1", "windows": [xterm]})
        self.assertEqual(
            self.guest_script(), ["/bin/sh", "-c", gui.WINDOW_WAIT, "sbx", "class", "^xterm$"]
        )
        self.dispatch("window", "wait", "t1", "--name=-x", "--timeout", "2m")
        self.assertEqual(self.guest_script()[4:], ["name", "-x"])
        self.guest_prints(line + b"\n" + line.replace(b"4194", b"77") + b"\n")
        result, _ = self.dispatch("window", "list", "t1")
        listed = cast("dict[str, list[dict[str, object]]]", result)["windows"]
        self.assertEqual([window["id"] for window in listed], [4194, 77])
        self.assertEqual(self.guest_script(), ["/bin/sh", "-c", gui.WINDOW_LIST, "sbx"])
        self.guest_prints(line + b"\n")
        result, _ = self.dispatch("window", "focus", "t1", "--id", "4194")
        self.assertEqual(result, {"sandbox": "t1", "window": xterm})
        self.assertEqual(
            self.guest_script(), ["/bin/sh", "-c", gui.WINDOW_FOCUS, "sbx", "id", "4194"]
        )
        self.dispatch("window", "focus", "t1", "--name", "xterm")
        self.assertEqual(self.guest_script()[4:], ["name", "xterm"])

    def test_window_failures(self) -> None:
        """Malformed guest lines, refusals in the guest, and timeouts are distinct errors."""
        self.sandboxes().create(self.request(gui=True))
        good = b"1 WINDOW=1 X=0 Y=0 WIDTH=1 HEIGHT=1 SCREEN=0 eA=="
        malformed = [
            b"1 WINDOW=2 X=0 Y=0 WIDTH=1 HEIGHT=1 SCREEN=0 eA==",
            b"1 WINDOW=1 X=0 Y=0 WIDTH=1 HEIGHT=1 SCREEN=0 eA=",
            b"1 WINDOW=1 X=0 Y=0 WIDTH=-1 HEIGHT=1 SCREEN=0 ",
            good + b" extra",
            b"rm -rf /",
        ]
        for output in malformed:
            self.guest_prints(output + b"\n")
            with self.subTest(output=output), self.assertRaises(SbxError) as refused:
                self.dispatch("window", "list", "t1")
            self.assertEqual(refused.exception.code, "agent-reply")
        self.guest_prints(good + b"\n")
        with self.assertRaises(SbxError) as refused:
            self.dispatch("window", "wait", "t1", "--name", "x")
        self.assertEqual(refused.exception.code, "agent-reply")
        cases = [
            (gui.INVALID_EXIT, ("window", "wait", "t1", "--name", "("), "invalid-argument"),
            (gui.INVALID_EXIT, ("mouse", "t1", "--to", "5000,5"), "invalid-argument"),
            (gui.MISSING_EXIT, ("window", "focus", "t1", "--id", "9"), "no-window"),
            (1, ("window", "list", "t1"), "guest-command"),
            (1, ("mouse", "t1", "--to", "1,1"), "guest-command"),
        ]
        for code, argv, error in cases:
            self.guest_prints(b"", code)
            with self.subTest(argv=argv), self.assertRaises(SbxError) as refused:
                self.dispatch(*argv)
            self.assertEqual(refused.exception.code, error)
        for stdout, words in ((b"ready\n", "no visible window"), (b"", "did not answer")):
            timed_out = model.ExecResult(None, stdout, b"", timed_out=True, killed=True)
            with (
                self.subTest(stdout=stdout),
                mock.patch.object(Sandboxes, "session_command", return_value=timed_out),
                self.assertRaises(SbxError) as refused,
            ):
                self.dispatch("window", "wait", "t1", "--class", "xterm", "--timeout", "1s")
            self.assertEqual(refused.exception.code, "window-timeout")
            self.assertIn(words, str(refused.exception))

    def test_window_refusals(self) -> None:
        """Bad coordinates, ids, and patterns, and bases without a display, run nothing."""
        self.sandboxes().create(self.request(gui=True))
        self.add_running("plain")
        cases = [
            (("mouse", "t1", "--to", "-1,5"), "invalid-argument"),
            (("mouse", "t1", "--to", "1;5"), "invalid-argument"),
            (("mouse", "t1", "--to", "40000,5"), "invalid-argument"),
            (("mouse", "t1"), "usage"),
            (("mouse", "t1", "--to", "1,1", "--click", "back"), "usage"),
            (("window", "wait", "t1"), "usage"),
            (("window", "wait", "t1", "--name", "a", "--class", "b"), "usage"),
            (("window", "wait", "t1", "--name", ""), "invalid-argument"),
            (("window", "wait", "t1", "--name", "x", "--timeout", "0s"), "invalid-argument"),
            (("window", "focus", "t1"), "usage"),
            (("window", "focus", "t1", "--id", "0"), "invalid-argument"),
            (("window", "focus", "t1", "--id", str(1 << 32)), "invalid-argument"),
            (("mouse", "plain", "--to", "1,1"), "no-display"),
            (("window", "wait", "plain", "--class", "xterm"), "no-display"),
            (("window", "focus", "plain", "--id", "1"), "no-display"),
            (("window", "list", "plain"), "no-display"),
        ]
        for argv, code in cases:
            with self.subTest(argv=argv), self.assertRaises(SbxError) as refused:
                self.dispatch(*argv)
            self.assertEqual(refused.exception.code, code)
        self.assertEqual(self.backend.execs, [])

    def prepared(self) -> Path:
        """Lay out a prepared debian-13 base."""
        disk = self.paths.bases / "debian-13" / "disk.qcow2"
        disk.parent.mkdir()
        disk.write_bytes(b"")
        return disk

    def seed(self) -> dict[str, object]:
        """Read the last seed the xorriso stub packed."""
        directory = self.scratch / "seed"
        return {path.name: path.read_text() for path in directory.iterdir()}

    def test_cloud_create(self) -> None:
        """A cloud sandbox boots the prepared disk with a NoCloud seed instead of fw_cfg."""
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request("debian-13"))
        self.assertEqual(refused.exception.code, "base-missing")
        self.assert_no_sandbox("t1")
        disk = self.prepared()
        result = self.sandboxes().create(self.request("debian-13"))
        self.assertEqual(result.base, "debian-13")
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        self.assertIsNone(root.find("sysinfo"))
        seed_iso = str(self.paths.sandbox("t1") / "seed.iso")
        source = root.find("devices/disk[@device='cdrom']/source")
        self.assertEqual(source.get("file"), seed_iso)  # pyright: ignore[reportOptionalMemberAccess]
        self.assertIsNotNone(root.find("devices/disk[@device='cdrom']/readonly"))
        self.assertTrue((self.paths.sandbox("t1") / "seed.iso").exists())
        self.assertFalse((self.paths.sandbox("t1") / "seed").exists())
        self.assertFalse((self.paths.sandbox("t1") / "base").exists())
        self.assertEqual(self.sandboxes().info("t1").image, str(disk))
        seed = self.seed()
        user_data = cast("str", seed["user-data"])
        self.assertTrue(user_data.startswith("#cloud-config\n"))
        config = json.loads(user_data.split("\n", 1)[1])
        self.assertEqual(config["ssh_authorized_keys"], ["ssh-ed25519 AAAA sbx"])
        self.assertEqual((config["users"], config["disable_root"]), ([], False))
        meta_data = json.loads(cast("str", seed["meta-data"]))
        self.assertTrue(meta_data["instance-id"].startswith("sbx-t1-"))
        self.assertEqual(
            json.loads(cast("str", seed["network-config"])), {"network": {"config": "disabled"}}
        )

    def test_cloud_egress_seed(self) -> None:
        """An egress cloud sandbox's seed runs DHCP on its NIC at the network's MTU."""
        self.prepared()
        self.egress().write_text(
            json.dumps([{"ip-address": "172.16.2.5", "mac-address": MAC, "expiry-time": 0}])
        )
        self.sandboxes().create(self.request("debian-13", net="egress"))
        network = json.loads(cast("str", self.seed()["network-config"]))["network"]
        self.assertEqual(
            network["ethernets"]["egress"],
            {"match": {"macaddress": MAC}, "dhcp4": True, "mtu": 1240},
        )

    def test_cloud_base_verbs(self) -> None:
        """Listing reports cloud bases, and building refuses them."""
        listed = {entry["base"]: entry for entry in self.sandboxes().base_list()}
        self.assertEqual(listed["debian-13"]["kind"], "cloud")
        self.assertFalse(listed["debian-13"]["built"])
        self.assertEqual(listed["nixos-gui"]["kind"], "nix")
        disk = self.prepared()
        listed = {entry["base"]: entry for entry in self.sandboxes().base_list()}
        self.assertEqual(listed["debian-13"]["path"], str(disk))
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().base_build("debian-13")
        self.assertEqual(refused.exception.code, "base-cloud")

    def prepare_egress(self) -> None:
        """Give the prepare boot a bridge and a lease for its MAC."""
        self.egress().write_text(
            json.dumps([{"ip-address": "172.16.2.5", "mac-address": MAC, "expiry-time": 0}])
        )

    def test_prepare(self) -> None:
        """A prepare fetches the pinned image, provisions it, and publishes the flattened disk."""
        self.prepare_egress()
        old = self.prepared()
        real_run = prepare.run
        flattened: list[bool] = []

        def run(argv: list[str]) -> str:
            if argv[1] == "convert":
                # The flatten runs without the state lock, so sleep is not stuck behind it.
                with self.sandboxes(None).locked(timeout=0):
                    flattened.append(True)
            return real_run(argv)

        with mock.patch.object(prepare, "run", side_effect=run):
            result = self.sandboxes(session=None).base_prepare("debian-13")
        self.assertEqual(flattened, [True])
        disk = self.paths.bases / "debian-13" / "disk.qcow2"
        self.assertEqual(result["path"], str(disk))
        self.assertTrue(disk.exists())
        self.assertEqual(disk.stat().st_mode & 0o777, 0o400)
        self.assertEqual(old, disk)
        # No staged or replaced directory remains.
        self.assertEqual(
            sorted(entry.name for entry in self.paths.bases.iterdir()),
            ["debian-13", "nixos", "nixos-gui"],
        )
        nix_args = (self.scratch / "nix.log").read_text().split()
        self.assertEqual(nix_args[:3], ["store", "prefetch-file", "--json"])
        self.assertIn("sha256-x", nix_args)
        self.assertIn("https://cloud.example/d.qcow2", nix_args)
        self.assert_no_sandbox("prepare-debian-13")
        xml = self.backend.xml["sbx-prepare-debian-13"]
        root = ET.fromstring(xml)  # noqa: S314
        self.assertEqual(root.find("devices/interface/source").get("bridge"), "vn-sbx")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertIsNotNone(root.find("devices/disk[@device='cdrom']"))

    def test_prepare_refusals(self) -> None:
        """Agents, unknown images, bases in use, and failed provisioning publish nothing."""
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().base_prepare("debian-13")
        self.assertEqual(refused.exception.code, "owner-only")
        with self.assertRaises(SbxError) as refused:
            self.sandboxes(session=None).base_prepare("nixos")
        self.assertEqual(refused.exception.code, "unknown-base")
        self.prepare_egress()
        owner = self.sandboxes(session=None)
        self.backend.add("user", expires=NOW + 60, base="debian-13")
        with self.assertRaises(SbxError) as refused:
            owner.base_prepare("debian-13")
        self.assertEqual(refused.exception.code, "base-in-use")
        self.backend.remove("sbx-user")
        with (
            mock.patch.dict(os.environ, {"SBX_TEST_PROVISION_EXIT": "3"}),
            self.assertRaises(SbxError) as refused,
        ):
            owner.base_prepare("debian-13")
        self.assertEqual(refused.exception.code, "prepare-failed")
        self.assertIn("exited 3", str(refused.exception))
        self.assert_no_sandbox("prepare-debian-13")
        self.assertFalse((self.paths.bases / "debian-13").exists())

    def test_prepare_refuses_external_files(self) -> None:
        """An image whose header names another host file never boots."""
        self.prepare_egress()
        owner = self.sandboxes(session=None)
        cases = {
            "backing file": {"format": "qcow2", "backing-filename": "/home/vx/.ssh/id_ed25519"},
            "data file": {
                "format": "qcow2",
                "format-specific": {"type": "qcow2", "data": {"data-file": "/etc/shadow"}},
            },
            "unreadable": "fail",
        }
        for case, info in cases.items():
            value = info if isinstance(info, str) else json.dumps(info)
            with (
                self.subTest(case=case),
                mock.patch.dict(os.environ, {"SBX_TEST_IMAGE_INFO": value}),
                self.assertRaises(SbxError) as refused,
            ):
                owner.base_prepare("debian-13")
            self.assertEqual(refused.exception.code, "image-unsafe")
            self.assertNotIn("sbx-prepare-debian-13", self.backend.xml)
            self.assertFalse(self.paths.sandbox("prepare-debian-13").exists())
            self.assertFalse((self.paths.bases / "debian-13").exists())


if __name__ == "__main__":
    unittest.main()
