# Copyright (c) 2026 Bad3r
"""Policy and lifecycle checks of sbx against a fake backend and stub tools."""

import dataclasses
import json
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, cast
from unittest import mock

from sbx import cli, core
from sbx.cloud import CloudImage
from sbx.core import NS, DomainInfo, Egress, Meta, Paths, Sandboxes, SbxError, Settings, Tools

NOW = 1_800_000_000
MAC = "52:54:00:ab:cd:ef"

STUBS = {
    "ssh-keygen": 'for k; do :; done; echo key > "$k"; echo "ssh-ed25519 AAAA sbx" > "$k.pub"',
    "nix-store": 'ln -s "$4" "$2"',
    "qemu-img": (
        'case "$1" in info) echo \'{"virtual-size": 1073741824}\';; '
        'convert) for t; do :; done; touch "$t";; '
        '*) eval "disk=\\${$(($# - 1))}"; touch "$disk";; esac'
    ),
    "ssh": (
        'case "$*" in *poweroff*) code="${SBX_TEST_PROVISION_EXIT:-0}"; '
        '[ "$code" = 0 ] && touch "$SBX_TEST_POWEROFF"; exit "$code";; esac; '
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
        'if [ -n "$SBX_TEST_BIG" ]; then exec head -c "$SBX_TEST_BIG" /dev/zero > "$t"; fi; '
        'if [ -n "$SBX_TEST_MANY" ]; then mkdir "$t"; for i in 1 2 3 4 5 6; do '
        'head -c "$SBX_TEST_MANY" /dev/urandom > "$t/$i"; sleep 0.4; done; '
        'touch "$SBX_TEST_DONE"; exit 0; fi; '
        'echo out > "$t"; chmod 755 "$t"'
    ),
    "ss": 'cat "$SBX_TEST_SS" 2>/dev/null || true',
    "git": (
        'if [ -n "$GIT_DIR" ] || [ -z "$SBX_TEST_TOPLEVEL" ]; then exit 1; fi; '
        'echo "$SBX_TEST_TOPLEVEL"'
    ),
    "other": "exit 0",
}


class FakeBackend:
    """Session domains held in memory."""

    def __init__(self) -> None:
        """Start empty."""
        self.domains_by_name: dict[str, DomainInfo] = {}
        self.xml: dict[str, str] = {}
        self.replies: list[dict[str, Any]] = []
        self.keys: list[tuple[str, list[int]]] = []

    def domains(self) -> list[DomainInfo]:
        """List the fake domains; a provisioning run over SSH has powered them all off."""
        if Path(os.environ["SBX_TEST_POWEROFF"]).exists():
            for name in list(self.domains_by_name):
                self.stop(name)
        return list(self.domains_by_name.values())

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
        )

    def remove(self, domain: str) -> None:
        """Forget a domain."""
        del self.domains_by_name[domain]

    def agent(self, domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:  # noqa: ARG002
        """Answer guest-ping, then the queued replies."""
        if command["execute"] == "guest-ping":
            return {"return": {}}
        return self.replies.pop(0)

    def screenshot(self, domain: str, target: Path) -> str:  # noqa: ARG002
        """Write a placeholder image."""
        target.write_bytes(b"png")
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
            nix=str(stubs / "nix"),
            nix_store=str(stubs / "nix-store"),
            xorriso=str(stubs / "xorriso"),
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
            vsock_allowlist=frozenset({7000}),
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
                "SBX_TEST_SS": str(self.scratch / "ss"),
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
        journal = mock.patch.object(core.journal, "record")
        journal.start()
        self.addCleanup(journal.stop)

    def sandboxes(self, session: str | None = "claude:one") -> Sandboxes:
        """Bind the fake backend at a fixed clock."""
        return Sandboxes(
            self.settings, self.paths, lambda _slice: self.backend, session, lambda: NOW
        )

    def request(self, base: str = "nixos", /, **overrides: Any) -> core.Request:  # noqa: ANN401
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
            {"net": "lan"},
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
        self.assertEqual(root.find("vcpu").get("cpuset"), "8-23")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("cputune/emulatorpin").get("cpuset"), "8-23")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("cpu/feature").get("name"), "vmx")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("features/vmport").get("state"), "off")  # pyright: ignore[reportOptionalMemberAccess]
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
        """Reachable host listeners outside the allowlist refuse a sandbox."""
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

    def checkout_root(self, toplevel: Path, **environment: str) -> Path | None:
        """Return the checkout root sbx derives from a reported toplevel."""
        with mock.patch.dict(os.environ, {"SBX_TEST_TOPLEVEL": str(toplevel), **environment}):
            return self.sandboxes().checkout()

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
        core.run([git, "init", "-q", str(repo)])
        cwd = Path.cwd()
        self.addCleanup(os.chdir, cwd)
        os.chdir(repo)
        with mock.patch.dict(os.environ, {"HOME": str(home)}):
            self.assertEqual(self.sandboxes().checkout(), repo.resolve())
            core.run([git, "config", "core.worktree", str(home)])
            self.assertIsNone(self.sandboxes().checkout())

    def add_running(self, name: str, *, expires: int = NOW + 60) -> None:
        """Register a running sandbox with its run directory."""
        (self.paths.sandbox(name) / "xfer").mkdir(parents=True)
        self.backend.add(name, expires=expires)

    def test_create_rechecks_ceilings(self) -> None:
        """A request built past the ceilings still fails at create."""
        request = core.Request("nixos", "t1", "none", 8192, 2, 3600)
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
        copied = Path(str(result["to"]))
        self.assertEqual(copied, self.paths.sandbox("c") / "xfer" / "tool")
        self.assertEqual(copied.stat().st_mode & 0o7777, 0o644)
        with self.assertRaises(SbxError) as refused:
            sandboxes.copy("c:/usr/bin/tool", None)
        self.assertEqual(refused.exception.code, "exists")
        target = self.scratch / "tmp"
        self.assertEqual(sandboxes.copy("c:/usr/bin/tool", str(target))["to"], str(target / "tool"))
        with self.assertRaises(SbxError):
            sandboxes.copy("c:/usr/bin/tool", str(target))
        self.assertEqual(list((self.paths.sandbox("c") / "xfer").glob(".stage-*")), [])

    def test_expired_sandboxes_refuse_access(self) -> None:
        """exec, cp, and screenshot refuse a sandbox past its TTL."""
        self.add_running("old", expires=NOW - 1)
        sandboxes = self.sandboxes()
        with self.assertRaises(SbxError) as refused:
            sandboxes.exec_capture("old", ["true"], timeout=None, agent=False)
        self.assertEqual(refused.exception.code, "expired")
        with self.assertRaises(SbxError):
            sandboxes.copy("old:/etc/hostname", None)
        with self.assertRaises(SbxError):
            sandboxes.screenshot("old", ocr=False)

    def test_agent_replies_are_validated(self) -> None:
        """Malformed qemu-ga replies fail with agent-reply; good ones decode."""
        self.add_running("g")
        sandboxes = self.sandboxes()
        good = {"exited": True, "exitcode": 3, "out-data": "aGk=", "err-data": ""}
        self.backend.replies = [{"return": {"pid": 7}}, {"return": good}]
        result = sandboxes.exec_capture("g", ["x"], timeout=None, agent=True)
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
                sandboxes.exec_capture("g", ["x"], timeout=None, agent=True)
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
        self.assertEqual(self.sandboxes().gc(dry_run=False), [{"name": "x", "reason": "no domain"}])
        self.assertIn("sbx-x", self.backend.domains_by_name)
        self.paths.sandbox("x").mkdir()
        self.sandboxes().destroy("x")
        self.assertIn("sbx-x", self.backend.domains_by_name)

    def dispatch(self, *argv: str) -> tuple[object, int]:
        """Run one verb through the command line, in JSON mode."""
        leading, command = cli.split_command(argv)
        args = cli.build_parser().parse_args(leading)
        args.command = command
        return cli.dispatch(self.sandboxes(), args, as_json=True)

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
        core.publish(first, target)
        with self.assertRaises(SbxError) as refused:
            core.publish(second, target)
        self.assertEqual(refused.exception.code, "exists")
        self.assertEqual(target.read_text(), "1")
        self.assertTrue(second.exists())

    def test_guest_timeout(self) -> None:
        """A timeout bounds the guest command too, with a later host backstop."""
        self.add_running("t")
        calls: list[tuple[list[str], float | None]] = []

        def fake(argv: list[str], _limit: int, timeout: float | None) -> core.ExecResult:
            calls.append((argv, timeout))
            return core.ExecResult(124, b"", b"", truncated=False, timed_out=False)

        with mock.patch.object(core, "capture", fake):
            result = self.sandboxes().exec_capture("t", ["sleep", "9"], timeout=2, agent=False)
        self.assertTrue(result.timed_out)
        argv, timeout = calls[0]
        self.assertEqual(argv[-1], "timeout --kill-after=5 2 sleep 9")
        self.assertEqual(timeout, 2 + core.HOST_BACKSTOP)

    def test_json_exit_codes(self) -> None:
        """The guest's status is the exit status of exec --json."""
        self.add_running("j")
        with mock.patch.dict(os.environ, {"SBX_TEST_SSH_EXIT": "3"}):
            result, code = self.dispatch("--json", "exec", "j", "--", "false")
        self.assertEqual(code, 3)
        self.assertEqual(cast("dict[str, object]", result)["exit_code"], 3)

    def test_run_refusals_before_create(self) -> None:
        """--out without --to, --to without --out, and a bad --timeout create nothing."""
        for argv in (
            ("run", "nixos", "--name", "r", "--out", "/x", "--", "true"),
            ("run", "nixos", "--name", "r", "--to", ".", "--", "true"),
            ("run", "nixos", "--name", "r", "--timeout", "5x", "--", "true"),
        ):
            with self.subTest(argv=argv), self.assertRaises(SbxError):
                self.dispatch(*argv)
            self.assert_no_sandbox("r")

    def test_run_destroys_on_failure(self) -> None:
        """A failed copy in, exec, or copy out still destroys the run sandbox."""
        outside = self.scratch / "outside"
        outside.mkdir()
        cases: list[tuple[tuple[str, ...], Any]] = [
            (("--in", str(outside)), None),
            ((), SbxError("boom", code="test")),
            (("--out", "/root/x", "--to", str(outside)), None),
        ]
        for flags, failure in cases:
            argv = ("run", "nixos", "--name", "r", *flags, "--", "true")
            patch = mock.patch.object(Sandboxes, "exec_capture", side_effect=failure)
            with self.subTest(flags=flags), self.assertRaises(SbxError):
                if failure is None:
                    self.dispatch(*argv)
                else:
                    with patch:
                        self.dispatch(*argv)
            self.assert_no_sandbox("r")

    def egress(self, flags: str = "0x1003") -> Path:
        """Configure vn-sbx with a fake sysfs entry and return its lease file."""
        sys_net = self.scratch / "sys-net"
        (sys_net / "vn-sbx" / "bridge").mkdir(parents=True)
        (sys_net / "vn-sbx" / "flags").write_text(f"{flags}\n")
        patch = mock.patch.object(core, "SYS_NET", sys_net)
        patch.start()
        self.addCleanup(patch.stop)
        leases = self.scratch / "vn-sbx.status"
        self.settings = dataclasses.replace(self.settings, egress=Egress("vn-sbx", leases))
        mac = mock.patch.object(core, "random_mac", return_value=MAC)
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
        device = core.SYS_NET / "vn-sbx"
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
        self.assertEqual((result["net"], result["address"]), ("egress", "172.16.2.5"))
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        interfaces = root.findall("devices/interface")
        self.assertEqual(len(interfaces), 1)
        interface = interfaces[0]
        self.assertEqual(interface.get("type"), "bridge")
        self.assertEqual(interface.find("source").get("bridge"), "vn-sbx")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(interface.find("model").get("type"), "virtio")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(interface.find("mac").get("address"), MAC)  # pyright: ignore[reportOptionalMemberAccess]
        listed = self.sandboxes().listing(mine=False)
        self.assertEqual([entry["address"] for entry in listed], ["172.16.2.5"])
        self.assertEqual(self.sandboxes().info("t1")["address"], "172.16.2.5")

    def test_egress_without_lease(self) -> None:
        """A guest that never takes a lease fails create with no-address and is discarded."""
        self.egress().write_text("")
        ticks = iter(range(NOW, NOW + 10_000, 2))
        sandboxes = Sandboxes(
            self.settings, self.paths, lambda _slice: self.backend, None, lambda: next(ticks)
        )
        with mock.patch.object(core.time, "sleep"), self.assertRaises(SbxError) as refused:
            sandboxes.create(self.request(net="egress"))
        self.assertEqual(refused.exception.code, "no-address")
        self.assert_no_sandbox("t1")

    def test_lease_file(self) -> None:
        """Missing and empty files hold no lease, malformed ones fail, IPv6 is skipped."""
        path = self.scratch / "leases"
        self.assertIsNone(core.lease_address(path, MAC, NOW))
        path.write_text("")
        self.assertIsNone(core.lease_address(path, MAC, NOW))
        entries = [
            {"ip-address": "fd00::5", "mac-address": MAC, "expiry-time": NOW + 60},
            {"ip-address": "172.16.2.3", "mac-address": MAC, "expiry-time": 0},
        ]
        path.write_text(json.dumps(entries))
        self.assertEqual(core.lease_address(path, MAC.upper(), NOW), "172.16.2.3")
        for text in ("{", "{}", "[1]", '[{"ip-address": "172.16.2.3"}]'):
            path.write_text(text)
            with self.subTest(text=text), self.assertRaises(SbxError) as refused:
                core.lease_address(path, MAC, NOW)
            self.assertEqual(refused.exception.code, "lease-file")

    def test_malformed_leases(self) -> None:
        """A bad lease file leaves the address out of a listing but fails create."""
        leases = self.egress()
        leases.write_text(
            json.dumps([{"ip-address": "172.16.2.5", "mac-address": MAC, "expiry-time": 0}])
        )
        self.sandboxes().create(self.request(net="egress"))
        leases.write_text("{")
        self.assertEqual(
            [entry["address"] for entry in self.sandboxes().listing(mine=False)], [None]
        )
        self.assertIsNone(self.sandboxes().info("t1")["address"])
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request(name="t2", net="egress"))
        self.assertEqual(refused.exception.code, "lease-file")
        self.assert_no_sandbox("t2")

    def test_none_has_no_address(self) -> None:
        """A sandbox without a NIC reports no address even with egress configured."""
        self.egress()
        result = self.sandboxes().create(self.request())
        self.assertIsNone(result["address"])
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        self.assertIsNone(root.find("devices/interface"))

    def test_egress_checks_vsock_listeners(self) -> None:
        """A NIC does not remove vsock, so egress sandboxes get the listener check too."""
        self.egress()
        (self.scratch / "ss").write_text("v_str LISTEN 0 0 2:5999 *:*\n")
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request(net="egress"))
        self.assertEqual(refused.exception.code, "vsock-listener")

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
            },
            "defaults": {
                "memoryMiB": 1,
                "guiMemoryMiB": 2,
                "cpus": 1,
                "ttlSeconds": 1,
                "diskGiB": 1,
            },
            "vsockAllowlist": [],
            "cpuset": "0",
            "flake": "/flake",
            "unit": "u",
            "slice": "s",
            "outputLimit": 1,
            "bootTimeout": 1,
            "egress": {"bridge": "vn-sbx", "leases": "/leases"},
            "cloudImages": {"debian-13": {"url": "https://x/d.qcow2", "hash": "sha256-y"}},
            "tools": dataclasses.asdict(self.settings.tools),
        }
        path = self.scratch / "settings.json"
        path.write_text(json.dumps(raw))
        loaded = Settings.load(path)
        self.assertEqual(loaded.egress, Egress("vn-sbx", Path("/leases")))
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
        """Chords and text reach the display as Linux keycodes, one send per chord."""
        self.sandboxes().create(self.request(gui=True))
        with mock.patch.object(core.time, "sleep"):
            result, _ = self.dispatch("key", "t1", "ctrl+alt+t", "Enter")
            self.assertEqual(result, {"sandbox": "t1", "keys": ["ctrl+alt+t", "Enter"]})
            result, _ = self.dispatch("type", "t1", "Hi!\n")
            self.assertEqual(result, {"sandbox": "t1", "characters": 4})
        self.assertEqual(
            [codes for _domain, codes in self.backend.keys],
            [[29, 56, 20], [28], [42, 35], [23], [42, 2], [28]],
        )
        self.assertEqual({domain for domain, _codes in self.backend.keys}, {"sbx-t1"})

    def test_input_refusals(self) -> None:
        """Unknown keys, untypable text, and sandboxes without a display send nothing."""
        self.sandboxes().create(self.request(gui=True))
        self.add_running("plain")
        self.backend.add("old", expires=NOW - 1, base="nixos-gui")
        cases = [
            (("key", "t1", "ctrl+nope"), "invalid-argument"),
            (("key", "t1", "+".join(["a"] * 17)), "invalid-argument"),
            (("type", "t1", "x\u00e9"), "invalid-argument"),
            (("type", "t1", "a\rb"), "invalid-argument"),
            (("key", "plain", "enter"), "no-display"),
            (("type", "plain", "x"), "no-display"),
            (("key", "old", "enter"), "expired"),
        ]
        for argv, code in cases:
            with self.subTest(argv=argv), self.assertRaises(SbxError) as refused:
                self.dispatch(*argv)
            self.assertEqual(refused.exception.code, code)
        self.assertEqual(self.backend.keys, [])

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
        self.assertEqual(result["base"], "debian-13")
        root = ET.fromstring(self.backend.xml["sbx-t1"])  # noqa: S314
        self.assertIsNone(root.find("sysinfo"))
        seed_iso = str(self.paths.sandbox("t1") / "seed.iso")
        source = root.find("devices/disk[@device='cdrom']/source")
        self.assertEqual(source.get("file"), seed_iso)  # pyright: ignore[reportOptionalMemberAccess]
        self.assertIsNotNone(root.find("devices/disk[@device='cdrom']/readonly"))
        self.assertTrue((self.paths.sandbox("t1") / "seed.iso").exists())
        self.assertFalse((self.paths.sandbox("t1") / "seed").exists())
        self.assertFalse((self.paths.sandbox("t1") / "base").exists())
        self.assertEqual(self.sandboxes().info("t1")["image"], str(disk))
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
        """An egress cloud sandbox leaves networking to cloud-init's DHCP fallback."""
        self.prepared()
        self.egress().write_text(
            json.dumps([{"ip-address": "172.16.2.5", "mac-address": MAC, "expiry-time": 0}])
        )
        self.sandboxes().create(self.request("debian-13", net="egress"))
        self.assertNotIn("network-config", self.seed())

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
        result = self.sandboxes(session=None).base_prepare("debian-13")
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


if __name__ == "__main__":
    unittest.main()
