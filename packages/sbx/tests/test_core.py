# Copyright (c) 2026 Bad3r
"""Policy and lifecycle checks of sbx against a fake backend and stub tools."""

import dataclasses
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any
from unittest import mock

from sbx import core
from sbx.core import NS, DomainInfo, Meta, Paths, Sandboxes, SbxError, Settings, Tools

NOW = 1_800_000_000

STUBS = {
    "ssh-keygen": 'for k; do :; done; echo key > "$k"; echo "ssh-ed25519 AAAA sbx" > "$k.pub"',
    "nix-store": 'ln -s "$4" "$2"',
    "qemu-img": (
        'if [ "$1" = info ]; then echo \'{"virtual-size": 1073741824}\'; '
        'else eval "disk=\\${$(($# - 1))}"; touch "$disk"; fi'
    ),
    "ssh": "exit 0",
    "scp": 'printf "%s\\n" "$@" > "$SBX_TEST_LOG"',
    "ss": 'cat "$SBX_TEST_SS" 2>/dev/null || true',
    "git": "exit 1",
    "other": "exit 0",
}


class FakeBackend:
    """Session domains held in memory."""

    def __init__(self) -> None:
        """Start empty."""
        self.domains_by_name: dict[str, DomainInfo] = {}
        self.xml: dict[str, str] = {}

    def domains(self) -> list[DomainInfo]:
        """List the fake domains."""
        return list(self.domains_by_name.values())

    def add(self, name: str, *, expires: int, active: bool = True, **kwargs: Any) -> None:  # noqa: ANN401
        """Insert a domain as if sbx had created it."""
        meta = Meta(
            "nixos", "/nix/store/x/sbx.qcow2", "none", NOW - 60, expires, kwargs.get("session")
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
        )

    def start(self, xml: str) -> None:
        """Record the XML and treat the domain as running."""
        root = ET.fromstring(xml)  # noqa: S314
        name = root.findtext("name", "")
        element = root.find(f"metadata/{{{NS}}}sandbox")
        if element is None:
            raise AssertionError
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
        )

    def remove(self, domain: str) -> None:
        """Forget a domain."""
        del self.domains_by_name[domain]

    def agent(self, domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:  # noqa: ARG002
        """Answer every guest-ping."""
        return {"return": {}}

    def screenshot(self, domain: str, target: Path) -> str:  # noqa: ARG002
        """Write a placeholder image."""
        target.write_bytes(b"png")
        return "image/png"


class SandboxesTest(unittest.TestCase):
    """Ceilings, rendering, removal, and copy roots."""

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
            emulator="/nix/store/qemu/bin/qemu-system-x86_64",
            qemu_img=str(stubs / "qemu-img"),
            ssh=str(stubs / "ssh"),
            scp=str(stubs / "scp"),
            ssh_keygen=str(stubs / "ssh-keygen"),
            socat=other,
            tesseract=other,
            ss=str(stubs / "ss"),
            git=str(stubs / "git"),
            systemctl=other,
            nix=other,
            nix_store=str(stubs / "nix-store"),
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
            default_cpus=2,
            default_ttl=2 * 3600,
            disk_gib=20,
            vsock_allowlist=frozenset({7000}),
            flake="/flake",
            unit="sbx-libvirt.service",
            slice="sbx.slice",
            output_limit=1024,
            boot_timeout=5,
            tools=tools,
        )
        self.paths = Paths(self.scratch / "data" / "sbx", self.scratch / "config")
        image = self.scratch / "store" / "base"
        image.mkdir(parents=True)
        (image / "sbx-nixos.qcow2").write_bytes(b"")
        self.paths.bases.mkdir(parents=True)
        (self.paths.bases / "nixos").symlink_to(image)
        self.backend = FakeBackend()
        self.environment = mock.patch.dict(
            os.environ,
            {
                "TMPDIR": str(self.scratch / "tmp"),
                "SBX_TEST_SS": str(self.scratch / "ss"),
                "SBX_TEST_LOG": str(self.scratch / "scp.log"),
            },
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        (self.scratch / "tmp").mkdir()
        journal = mock.patch.object(core.journal, "record")
        journal.start()
        self.addCleanup(journal.stop)

    def sandboxes(self, session: str | None = "claude:one") -> Sandboxes:
        """Bind the fake backend at a fixed clock."""
        return Sandboxes(
            self.settings, self.paths, lambda _slice: self.backend, session, lambda: NOW
        )

    def request(self, **overrides: Any) -> core.Request:  # noqa: ANN401
        """Validate create flags with defaults."""
        flags: dict[str, Any] = {
            "name": "t1",
            "net": "none",
            "memory": None,
            "cpus": None,
            "ttl": None,
        }
        flags.update(overrides)
        return self.sandboxes().request("nixos", **flags)

    def test_parsers(self) -> None:
        """Durations and sizes accept their units."""
        self.assertEqual(core.parse_duration("90"), 90)
        self.assertEqual(core.parse_duration("30m"), 1800)
        self.assertEqual(core.parse_duration("2h"), 7200)
        self.assertEqual(core.parse_memory("2G"), 2048)
        self.assertEqual(core.parse_memory("512m"), 512)
        with self.assertRaises(SbxError):
            core.parse_duration("2 hours")

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
            {"net": "egress"},
        ):
            with self.subTest(overrides=overrides), self.assertRaises(SbxError):
                self.request(**overrides)

    def test_create_renders_an_untrusted_domain(self) -> None:
        """The domain has no NIC, no vdagent, a disposable disk, and the root key credential."""
        result = self.sandboxes().create(self.request(ttl="1h"))
        self.assertEqual(result["name"], "t1")
        self.assertEqual(result["ttl_left"], 3600)
        self.assertEqual(result["session"], "claude:one")
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        self.assertIsNone(root.find("devices/interface"))
        self.assertIsNone(root.find("devices/graphics"))
        channels = [target.get("name") for target in root.iterfind("devices/channel/target")]
        self.assertEqual(channels, ["org.qemu.guest_agent.0"])
        self.assertEqual(root.find("devices/disk/driver").get("cache"), "unsafe")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("devices/vsock/cid").get("auto"), "yes")  # pyright: ignore[reportOptionalMemberAccess]
        entry = root.find("sysinfo/entry")
        self.assertEqual(entry.get("name"), core.CREDENTIAL)  # pyright: ignore[reportOptionalMemberAccess]
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

    def test_vsock_listeners(self) -> None:
        """Reachable host listeners outside the allowlist refuse a `none` sandbox."""
        ss = self.scratch / "ss"
        ss.write_text("v_str LISTEN 0 0 *:7000 *:*\nv_str LISTEN 0 0 1:5000 *:*\n")
        self.sandboxes().create(self.request())
        ss.write_text("v_str LISTEN 0 0 2:5999 *:*\n")
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request(name="t2"))
        self.assertEqual(refused.exception.code, "vsock-listener")

    def test_gc(self) -> None:
        """Expired, stopped, and directory-less sandboxes go; managed saves and live ones stay."""
        for name in ("live", "old", "off", "saved"):
            self.paths.sandbox(name).mkdir(parents=True)
        self.backend.add("live", expires=NOW + 60)
        self.backend.add("old", expires=NOW - 1)
        self.backend.add("off", expires=NOW + 60, active=False)
        self.backend.add("saved", expires=NOW + 60, active=False, managed_save=True)
        self.backend.add("lost", expires=NOW + 60)
        self.paths.sandbox("stray").mkdir()
        sandboxes = self.sandboxes()
        planned = sandboxes.gc(dry_run=True)
        self.assertEqual(len(self.backend.domains()), 5)
        self.assertTrue(self.paths.sandbox("stray").exists())
        self.assertEqual(sandboxes.gc(dry_run=False), planned)
        reasons = {action["name"]: action["reason"] for action in planned}
        self.assertEqual(
            reasons,
            {
                "old": "expired",
                "off": "shut off",
                "lost": "run directory missing",
                "stray": "no domain",
            },
        )
        self.assertEqual(sorted(self.backend.domains_by_name), ["sbx-live", "sbx-saved"])
        self.assertFalse(self.paths.sandbox("stray").exists())

    def test_destroy_mine(self) -> None:
        """--mine removes only the caller's sandboxes."""
        for name, session in (("a", "claude:one"), ("b", "codex:two")):
            self.paths.sandbox(name).mkdir(parents=True)
            self.backend.add(name, expires=NOW + 60, session=session)
        self.assertEqual(self.sandboxes().destroy_where(mine=True, expired=False), ["a"])
        self.assertEqual(sorted(self.backend.domains_by_name), ["sbx-b"])
        with self.assertRaises(SbxError):
            self.sandboxes(session=None).listing(mine=True)

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
        self.assertEqual(result["to"], "c:/root/")
        outside = self.scratch / "secret"
        outside.write_text("x")
        with self.assertRaises(SbxError) as refused:
            sandboxes.copy(str(outside), "c:/root/")
        self.assertEqual(refused.exception.code, "path-denied")
        (inside / "escape").symlink_to(outside)
        with self.assertRaises(SbxError):
            sandboxes.copy(str(inside), "c:/root/")
        result = sandboxes.copy("c:/var/log/messages", None)
        self.assertEqual(result["to"], str(self.paths.sandbox("c") / "xfer" / "messages"))
        with self.assertRaises(SbxError):
            sandboxes.copy("c:/etc/passwd", str(outside))


if __name__ == "__main__":
    unittest.main()
