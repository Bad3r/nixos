# Copyright (c) 2026 Bad3r
"""Runtime shares of sandboxes against the core tests' fake backend."""

import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import cast

from sbx import cli
from sbx.core import SbxError
from sbx.shares import Shares, attached

from tests.test_core import NOW, FakeBackend, Fixture


class ShareFake(FakeBackend):
    """Adds live virtiofs devices; a detached one lingers for `linger` polls, or forever."""

    def __init__(self) -> None:
        """No device is attached."""
        super().__init__()
        self.devices: dict[str, list[str]] = {}
        self.releasing: dict[str, tuple[str, int | None]] = {}
        self.linger: int | None = 2

    def live_xml(self, domain: str) -> str:
        """The devices, wrapped like a domain definition."""
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
        self.devices[domain].remove(xml)
        self.releasing[domain] = (xml, self.linger)


class SharesTest(Fixture):
    """xfer read-write, declared directories read-only, nothing else."""

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
        (self.paths.sandbox(name) / "xfer").mkdir(parents=True)
        self.backend.add(name, expires=expires)

    def device(self, tag: str) -> ET.Element:
        """The live device of a tag."""
        return ET.fromstring(attached(self.backend.live_xml("sbx-s"))[tag].xml)  # noqa: S314

    def test_attach(self) -> None:
        """The xfer directory attaches read-write, a declared one read-only, through virtiofsd."""
        self.add_running("s")
        xfer = self.shares().attach("s", "xfer")
        self.assertEqual(
            xfer,
            {
                "sandbox": "s",
                "tag": "xfer",
                "read_only": False,
                "host_path": str(self.paths.sandbox("s") / "xfer"),
                "attached": True,
            },
        )
        self.assertIsNone(self.device("xfer").find("readonly"))
        binary = self.device("xfer").find("binary")
        self.assertEqual(binary.get("path"), self.settings.tools.virtiofsd)  # pyright: ignore[reportOptionalMemberAccess]
        self.assertTrue(self.shares().attach("s", "docs")["read_only"])
        self.assertIsNotNone(self.device("docs").find("readonly"))
        with self.assertRaises(SbxError) as refused:
            self.shares().attach("s", "xfer")
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
            ("old", "xfer", "expired"),
            ("off", "xfer", "not-running"),
            ("missing", "xfer", "path-denied"),
        ]
        (self.paths.sandbox("off") / "xfer").mkdir(parents=True)
        for name, tag, expected in cases:
            with self.subTest(name=name, tag=tag), self.assertRaises(SbxError) as refused:
                self.shares().attach(name, tag)
            self.assertEqual(refused.exception.code, expected)
        self.assertEqual(self.backend.devices, {})

    def test_detach(self) -> None:
        """Detach waits for the guest to release the device; a held device is an error."""
        self.add_running("s")
        self.shares().attach("s", "docs")
        detached = self.shares().detach("s", "docs")
        self.assertEqual(
            (detached["attached"], detached["read_only"], detached["host_path"]),
            (False, True, str(self.docs)),
        )
        self.assertEqual(self.slept, [0.5, 0.5])
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "docs")
        self.assertEqual(refused.exception.code, "not-attached")
        self.shares().attach("s", "xfer")
        self.backend.linger = None
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "xfer")
        self.assertEqual(refused.exception.code, "detach-pending")

    def test_detach_saved(self) -> None:
        """A saved sandbox brings its shares back at restore, so detach refuses it."""
        self.backend.add("z", expires=NOW + 60, active=False, managed_save=True)
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("z", "xfer")
        self.assertEqual(refused.exception.code, "saved")

    def test_command_line(self) -> None:
        """`share attach` returns the share's JSON form."""
        self.add_running("s")
        args = cli.build_parser().parse_args(["share", "attach", "--json", "s", "xfer"])
        result, code = cli.dispatch(self.sandboxes(), args, as_json=True)
        self.assertEqual((code, cast("dict[str, object]", result)["attached"]), (0, True))


if __name__ == "__main__":
    unittest.main()
