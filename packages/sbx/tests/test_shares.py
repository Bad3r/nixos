# Copyright (c) 2026 Bad3r
"""Runtime shares of sandboxes against the core tests' fake backend."""

import dataclasses
import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import cast
from unittest import mock

from sbx.errors import SbxError
from sbx.sandboxes import Sandboxes
from sbx.shares import Shares, attached
from sbx.windows import WindowsSettings

from tests.test_core import NOW, FakeBackend, Fixture, dispatch


class ShareFake(FakeBackend):
    """Adds live virtiofs devices; a detached one lingers for `linger` polls, or forever."""

    def __init__(self) -> None:
        """No device is attached."""
        super().__init__()
        self.devices: dict[str, list[str]] = {}
        self.releasing: dict[str, tuple[str, int | None]] = {}
        self.linger: int | None = 2
        self.stuck: set[str] = set()
        self.vanished: set[str] = set()

    def live_xml(self, domain: str) -> str:
        """The devices, wrapped like a domain definition."""
        if domain in self.vanished:
            msg = f"no domain {domain}"
            raise SbxError(msg, code="not-found")
        devices = list(self.devices.get(domain, []))
        if domain in self.releasing:
            xml, left = self.releasing[domain]
            if left == 0:
                del self.releasing[domain]
            else:
                devices.append(xml)
                self.releasing[domain] = (xml, None if left is None else left - 1)
        return f"<domain><devices>{''.join(devices)}</devices></domain>"

    def attach_device(self, domain: str, xml: str) -> None:
        """Plug the device."""
        self.devices.setdefault(domain, []).append(xml)

    def detach_device(self, domain: str, xml: str) -> None:
        """Start releasing the device."""
        if domain in self.vanished:
            msg = f"no domain {domain}"
            raise SbxError(msg, code="not-found")
        self.devices[domain].remove(xml)
        self.releasing[domain] = (xml, None if domain in self.stuck else self.linger)


class SharesTest(Fixture):
    """shared read-write, declared directories read-only, nothing else."""

    def setUp(self) -> None:
        """Swap in the share-aware backend and write a policy file."""
        super().setUp()
        self.backend = ShareFake()
        self.docs = self.scratch / "docs"
        self.docs.mkdir()
        self.policy = self.scratch / "grants.json"
        declared = {
            "docs": self.docs,
            "home": Path.home(),
            "state": self.paths.root,
            "above": self.paths.root.parent,
            "gone": self.scratch / "gone",
        }
        self.policy.write_text(
            json.dumps({"sandboxShares": {k: {"hostPath": str(v)} for k, v in declared.items()}})
        )
        self.slept: list[float] = []
        self.now = 0.0

    def shares(self) -> Shares:
        """Shares over the fixture with a fake clock."""

        def sleep(seconds: float) -> None:
            self.slept.append(seconds)
            self.now += seconds

        return Shares(self.sandboxes(), self.policy, sleep=sleep, clock=lambda: self.now)

    def add_running(self, name: str, *, expires: int = NOW + 60) -> None:
        """Register a running sandbox with its run directory."""
        self.paths.sandbox(name).mkdir(parents=True)
        self.backend.add(name, expires=expires)

    def device(self, tag: str) -> ET.Element:
        """The live device of a tag."""
        return ET.fromstring(attached(self.backend.live_xml("sbx-s"))[tag].xml)  # noqa: S314

    def test_attach(self) -> None:
        """The shared directory attaches read-write, a declared one read-only, through virtiofsd."""
        self.add_running("s")
        shared = self.shares().attach("s", "shared")
        self.assertEqual(
            shared.as_json(),
            {
                "sandbox": "s",
                "tag": "shared",
                "read_only": False,
                "host_path": str(self.paths.sandbox("s").resolve() / "shared"),
                "attached": True,
            },
        )
        self.assertTrue((self.paths.sandbox("s") / "shared").is_dir())
        self.assertIsNone(self.device("shared").find("readonly"))
        binary = self.device("shared").find("binary")
        self.assertEqual(binary.get("path"), self.settings.tools.virtiofsd)  # pyright: ignore[reportOptionalMemberAccess]
        self.assertTrue(self.shares().attach("s", "docs").read_only)
        self.assertIsNotNone(self.device("docs").find("readonly"))
        with self.assertRaises(SbxError) as refused:
            self.shares().attach("s", "shared")
        self.assertEqual(refused.exception.code, "already-attached")
        self.journal_record.assert_any_call(
            "share docs attached to s",
            verb="share",
            sandbox="s",
            share="docs",
            read_only=True,
            session="claude:one",
        )

    def test_refusals(self) -> None:
        """Undeclared names, $HOME, the state directory, and stopped sandboxes are refused."""
        self.add_running("s")
        self.add_running("old", expires=NOW - 1)
        self.backend.add("off", expires=NOW + 60, active=False)
        cases = [
            ("s", "nope", "not-declared"),
            ("s", str(self.docs), "not-declared"),
            ("s", "home", "path-denied"),
            ("s", "state", "path-denied"),
            ("s", "above", "path-denied"),
            ("s", "gone", "path-denied"),
            ("s", "xfer", "not-declared"),
            ("old", "shared", "expired"),
            ("off", "shared", "not-running"),
            ("missing", "shared", "not-found"),
        ]
        self.paths.sandbox("off").mkdir(parents=True)
        for name, tag, expected in cases:
            with self.subTest(name=name, tag=tag), self.assertRaises(SbxError) as refused:
                self.shares().attach(name, tag)
            self.assertEqual(refused.exception.code, expected)
        self.assertEqual(self.backend.devices, {})

    def test_windows_refused(self) -> None:
        """A sandbox of a Windows base takes no share."""
        self.settings = dataclasses.replace(
            self.settings,
            windows=WindowsSettings("/firmware", 4096, {"win11": self.scratch}, "sbx-base"),
        )
        self.backend.add("w", expires=NOW + 60, base="win11")
        self.paths.sandbox("w").mkdir(parents=True)
        with self.assertRaises(SbxError) as refused:
            self.shares().attach("w", "shared")
        self.assertEqual(refused.exception.code, "unsupported-guest")
        self.assertEqual(self.backend.devices, {})

    def test_detach(self) -> None:
        """Detach waits for the guest to release the device; a held device is an error."""
        self.add_running("s")
        self.shares().attach("s", "docs")
        detached = self.shares().detach("s", "docs")
        self.assertEqual(
            (detached.attached, detached.read_only, detached.host_path),
            (False, True, str(self.docs)),
        )
        self.assertEqual(self.slept, [0.5, 0.5])
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "docs")
        self.assertEqual(refused.exception.code, "not-attached")
        self.shares().attach("s", "shared")
        self.backend.linger = None
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "shared")
        self.assertEqual(refused.exception.code, "detach-pending")

    def test_detach_saved(self) -> None:
        """A saved sandbox brings its shares back at restore, so detach refuses it."""
        self.backend.add("z", expires=NOW + 60, active=False, managed_save=True)
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("z", "shared")
        self.assertEqual(refused.exception.code, "saved")

    def test_disk_cap(self) -> None:
        """Past the cap, shared refuses to attach and gc detaches it; read-only shares stay."""
        self.add_running("s")
        self.add_running("t")
        shares = self.shares()
        shares.attach("s", "shared")
        shares.attach("s", "docs")
        shares.attach("t", "docs")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=0)
        (self.paths.sandbox("s") / "shared" / "fill").write_bytes(b"x" * 8192)
        with self.assertRaises(SbxError) as refused:
            self.shares().attach("t", "shared")
        self.assertEqual(refused.exception.code, "disk-full")
        self.assertEqual([action.name for action in self.shares().reclaim(dry_run=True)], ["s"])
        self.assertIn("shared", attached(self.backend.live_xml("sbx-s")))
        self.backend.linger = 0
        with mock.patch.object(Sandboxes, "host_synced", return_value=True):
            result, _ = dispatch(self.sandboxes(), "gc", "--json")
        self.assertEqual([action["name"] for action in cast("list[dict[str, str]]", result)], ["s"])
        self.assertEqual(set(attached(self.backend.live_xml("sbx-s"))), {"docs"})
        self.assertEqual(set(attached(self.backend.live_xml("sbx-t"))), {"docs"})

    def test_reclaim_continues_past_a_held_share(self) -> None:
        """A guest that keeps shared is reported, and the next sandbox still loses it."""
        self.add_running("s")
        self.add_running("t")
        for name in ("s", "t"):
            self.shares().attach(name, "shared")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=0)
        (self.paths.sandbox("s") / "shared" / "fill").write_bytes(b"x" * 8192)
        self.backend.stuck.add("sbx-s")
        actions = self.shares().reclaim(dry_run=False)
        self.assertEqual([action.name for action in actions], ["s", "t"])
        self.assertIn("detach-pending", actions[0].reason)
        self.assertNotIn("shared", attached(self.backend.live_xml("sbx-t")))

    def test_reclaim_skips_a_vanished_sandbox(self) -> None:
        """A domain another client removes mid-reclaim is skipped, before or after its lookup."""
        for name in ("s", "t", "u"):
            self.add_running(name)
            self.shares().attach(name, "shared")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=0)
        (self.paths.sandbox("s") / "shared" / "fill").write_bytes(b"x" * 8192)
        self.backend.vanished.add("sbx-s")
        self.backend.linger = 0
        real = self.backend.live_xml

        def vanish_t(domain: str) -> str:
            xml = real(domain)
            if domain == "sbx-t":
                self.backend.vanished.add(domain)
            return xml

        with mock.patch.object(self.backend, "live_xml", side_effect=vanish_t):
            actions = self.shares().reclaim(dry_run=False)
        self.assertEqual([action.name for action in actions], ["u"])

    def test_command_line(self) -> None:
        """`share attach` returns the share's JSON form."""
        self.add_running("s")
        result, code = dispatch(self.sandboxes(), "share", "attach", "--json", "s", "shared")
        self.assertEqual((code, cast("dict[str, object]", result)["attached"]), (0, True))


if __name__ == "__main__":
    unittest.main()
