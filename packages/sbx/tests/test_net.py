# Copyright (c) 2026 Bad3r
"""`sbx net cut` against the core tests' fake backend."""

import dataclasses
import json
import unittest
import xml.etree.ElementTree as ET
from typing import cast
from unittest import mock

from sbx import lifecycle
from sbx.config import Egress
from sbx.errors import SbxError
from sbx.results import NetCutResult
from sbx.sandboxes import Sandboxes
from sbx.windows import WindowsSettings

from tests.test_core import MAC, NOW, FakeBackend, Fixture, dispatch

ADDRESS = "172.16.6.5"


class NetFake(FakeBackend):
    """Adds each domain's egress NIC, which the guest releases unless it `keeps` it."""

    def __init__(self) -> None:
        """No domain has a NIC yet."""
        super().__init__()
        self.nics: dict[str, str] = {}
        self.keeps = False
        self.events: list[str] = []

    def live_xml(self, domain: str) -> str:
        """The NIC, when the domain still holds it."""
        return f"<domain><devices>{self.nics.get(domain, '')}</devices></domain>"

    def update_device(self, domain: str, xml: str) -> None:
        """Take the new link state of the NIC."""
        super().update_device(domain, xml)
        self.events.append("link-down")
        self.nics[domain] = xml

    def remove_device(self, domain: str, xml: str) -> None:
        """Release the NIC that the XML names by MAC and bridge."""
        super().remove_device(domain, xml)
        self.events.append("unplug")
        if not self.keeps:
            del self.nics[domain]

    def set_metadata(self, domain: str, xml: str) -> None:
        """Replace the metadata."""
        self.events.append("metadata")
        super().set_metadata(domain, xml)


class NetCutTest(Fixture):
    """An egress sandbox goes offline once and for good."""

    def setUp(self) -> None:
        """Register a running egress sandbox with a lease on the bridge."""
        super().setUp()
        leases = self.scratch / "leases.json"
        leases.write_text(
            json.dumps([{"ip-address": ADDRESS, "mac-address": MAC, "expiry-time": 0}])
        )
        self.settings = dataclasses.replace(self.settings, egress=Egress("vn-sbx", leases, 1400))
        self.backend = NetFake()
        self.backend.add("e", expires=NOW + 60, net="egress", mac=MAC)
        self.backend.nics["sbx-e"] = (
            f"<interface type='bridge'><mac address='{MAC}'/><source bridge='vn-sbx'/>"
            "<model type='virtio'/><alias name='net0'/></interface>"
        )
        self.paths.sandbox("e").mkdir(parents=True)
        revoke = mock.patch.object(lifecycle, "revoke_grants", side_effect=self.revoke)
        self.revoked = revoke.start()
        self.addCleanup(revoke.stop)
        self.now = 0.0

    def revoke(self, name: str, address: str | None) -> None:
        """Record the revoke in the backend's event order."""
        del name, address
        self.backend.events.append("revoke")

    def cut(self, name: str = "e") -> dict[str, object]:
        """Cut through the command line, on a fake monotonic clock."""
        sandboxes = self.sandboxes()

        def pause(seconds: float) -> None:
            self.now += seconds

        sandboxes.monotonic = lambda: self.now
        sandboxes.pause = pause
        result, _ = dispatch(sandboxes, "net", "cut", "--json", name)
        return cast("dict[str, object]", result)

    def test_cut(self) -> None:
        """Link down, unplug, revoke, then metadata; the sandbox then reports no address."""
        self.assertEqual(self.sandboxes().info("e").address, ADDRESS)
        result = self.cut()
        self.assertEqual(self.backend.events, ["link-down", "unplug", "revoke", "metadata"])
        self.assertEqual(
            result,
            {
                "sandbox": "e",
                "net": "none",
                "net_cut": "2027-01-15T08:00:00+00:00",
                "unplugged": True,
            },
        )
        self.revoked.assert_called_once_with("e", ADDRESS)
        ((_, updated),) = self.backend.updated
        self.assertEqual(ET.fromstring(updated).find("link").get("state"), "down")  # noqa: S314  # pyright: ignore[reportOptionalMemberAccess]
        ((_, removed),) = self.backend.removed
        self.assertEqual(
            removed,
            f'<interface type="bridge"><mac address="{MAC}" />'
            '<source bridge="vn-sbx" /></interface>',
        )
        meta = self.sandboxes().find("e").meta
        self.assertEqual((meta.net, meta.net_cut, meta.token), ("none", NOW, None))
        view = self.sandboxes().info("e")
        self.assertEqual((view.net, view.address), ("none", None))
        self.assertEqual(view.as_json()["net_cut"], "2027-01-15T08:00:00+00:00")

    def test_second_cut_refused(self) -> None:
        """A cut sandbox stays offline, and a second cut changes nothing."""
        self.cut()
        events = list(self.backend.events)
        with self.assertRaises(SbxError) as refused:
            self.cut()
        self.assertEqual(refused.exception.code, "invalid-argument")
        self.assertIn("already cut", str(refused.exception))
        self.assertEqual(self.backend.events, events)

    def test_offline_and_windows_refused(self) -> None:
        """A sandbox without egress and a Windows sandbox have no network to cut."""
        self.backend.add("n", expires=NOW + 60)
        self.settings = dataclasses.replace(
            self.settings,
            windows=WindowsSettings("/firmware", 4096, {"win11": self.scratch}, "sbx-base"),
        )
        self.backend.add("w", expires=NOW + 60, base="win11", net="egress", mac=MAC)
        for name in ("n", "w"):
            with self.subTest(name=name), self.assertRaises(SbxError) as refused:
                self.cut(name)
            self.assertEqual(refused.exception.code, "invalid-argument")
        self.assertEqual(self.backend.events, [])

    def test_guest_keeps_the_nic(self) -> None:
        """A NIC the guest keeps stays down; the cut still revokes and records net none."""
        self.backend.keeps = True
        result = self.cut()
        self.assertFalse(result["unplugged"])
        self.assertEqual(self.now, lifecycle.UNPLUG_WAIT)
        self.assertEqual(self.backend.events, ["link-down", "unplug", "revoke", "metadata"])
        self.assertIn("state='down'", self.backend.nics["sbx-e"].replace('"', "'"))
        self.assertIsNone(self.sandboxes().info("e").address)

    def test_failed_revoke_still_cuts(self) -> None:
        """A revoke the helper refuses fails the call after the sandbox is offline."""
        self.revoked.side_effect = SbxError("workload-grantd is unreachable", code="grants")
        with self.assertRaises(SbxError) as failed:
            self.cut()
        self.assertEqual(failed.exception.code, "grants")
        self.assertIn("is cut", str(failed.exception))
        self.assertEqual(self.sandboxes().find("e").meta.net, "none")

    def test_parser(self) -> None:
        """`net cut` takes one sandbox name."""
        done = NetCutResult("e", unplugged=True, net_cut="2027-01-15T08:00:00+00:00")
        with mock.patch.object(Sandboxes, "cut_network", return_value=done) as cut:
            dispatch(self.sandboxes(), "net", "cut", "e")
        cut.assert_called_once_with("e")


if __name__ == "__main__":
    unittest.main()
