# Copyright (c) 2026 Bad3r
"""Merging, status derivation, sorting, and degraded loads."""

import threading
import time
import unittest
from typing import TYPE_CHECKING, cast

from warp_devices.api import ApiError, Json
from warp_devices.devices import (
    CONNECTED,
    FLEET_STATUS,
    OFFLINE,
    PHYSICAL_DEVICES,
    REGISTRATIONS,
    UNKNOWN,
    latest_reports,
    load,
    merge,
)
from warp_devices.timefmt import DataError

from tests.fixtures import (
    NOW,
    FakeGetter,
    Handler,
    envelope,
    hardware,
    registration,
    report,
    static,
)

if TYPE_CHECKING:
    from collections.abc import Mapping

REGS = [
    registration("bravo", 1, minutes_ago=1),
    registration("alpha", 2, minutes_ago=30),
    registration("charlie", 3, minutes_ago=60 * 24 * 7),
    registration("delta", 4, minutes_ago=None),
]
HARDWARE = [hardware(1, name="bravo"), hardware(2, name="alpha", os_name="windows")]


def failing(path: str) -> Handler:
    """Return a handler that fails the way an exhausted retry does."""

    def handler(_params: Mapping[str, str]) -> Json:
        raise ApiError(path, "HTTP 503 after 5 attempts")

    return handler


class MergeTest(unittest.TestCase):
    """Each registration takes its newest report and its hardware fields."""

    def test_newest_report_wins(self) -> None:
        """An older disconnected report does not hide a newer connected one."""
        fleet = [report(1, "disconnected", 20), report(1, CONNECTED, 2)]
        device = merge(REGS, HARDWARE, latest_reports(fleet))[0]
        self.assertEqual((device.name, device.status), ("bravo", CONNECTED))

    def test_missing_report_is_offline(self) -> None:
        """A registration without a report in the window is offline."""
        statuses = {
            d.name: d.status
            for d in merge(REGS, HARDWARE, latest_reports([report(1, CONNECTED, 2)]))
        }
        self.assertEqual(statuses["alpha"], OFFLINE)

    def test_failed_fleet_is_unknown(self) -> None:
        """When DEX could not be read, every status is unknown."""
        self.assertEqual({d.status for d in merge(REGS, HARDWARE, None)}, {UNKNOWN})

    def test_registration_id_beats_device_id(self) -> None:
        """A report of another registration on the same device is not borrowed."""
        other = report(1, CONNECTED, 1)
        other["registrationId"] = "reg-99"
        self.assertEqual(merge(REGS, HARDWARE, latest_reports([other]))[0].status, OFFLINE)

    def test_device_id_fallback(self) -> None:
        """A report without a registration ID matches on the device ID."""
        fleet = [report(2, "disconnected", 5, registration_id=False)]
        statuses = {d.name: d.status for d in merge(REGS, HARDWARE, latest_reports(fleet))}
        self.assertEqual(statuses["alpha"], "disconnected")

    def test_nameless_registration_falls_back_to_ids(self) -> None:
        """A nameless registration takes its device ID, or its registration ID without one."""
        nameless = registration("unused", 7, minutes_ago=1)
        cast("Json", nameless["device"]).pop("name")
        deviceless = registration("unused", 8, minutes_ago=2)
        del deviceless["device"]
        names = {d.registration_id: d.name for d in merge([nameless, deviceless], [], None)}
        self.assertEqual(names, {"reg-7": "dev-7", "reg-8": "reg-8"})

    def test_hardware_fields(self) -> None:
        """Public IP and OS come from the physical device; absent hardware leaves them empty."""
        devices = {d.name: d for d in merge(REGS, HARDWARE, latest_reports([]))}
        self.assertEqual(
            (devices["alpha"].public_ip, devices["alpha"].os), ("203.0.113.2", "windows")
        )
        self.assertIsNone(devices["charlie"].public_ip)
        self.assertEqual(devices["bravo"].mesh_ipv4, "100.96.0.1")

    def test_sort_order(self) -> None:
        """Connected first, then most recently seen, never-seen last."""
        fleet = [report(2, CONNECTED, 1), report(1, "disconnected", 1)]
        names = [d.name for d in merge(REGS, HARDWARE, latest_reports(fleet))]
        self.assertEqual(names, ["alpha", "bravo", "charlie", "delta"])

    def test_sort_ties_by_name(self) -> None:
        """Equal last-seen times order by name, case-insensitively."""
        regs = [registration("Zulu", 1, minutes_ago=5), registration("echo", 2, minutes_ago=5)]
        self.assertEqual([d.name for d in merge(regs, [], latest_reports([]))], ["echo", "Zulu"])


class LoadTest(unittest.TestCase):
    """Registrations are required; the other endpoints degrade to warnings."""

    def routes(self, *, physical: bool = True, fleet: bool = True) -> FakeGetter:
        """Return a getter whose optional endpoints may fail."""
        return FakeGetter(
            {
                REGISTRATIONS: static(REGS),
                PHYSICAL_DEVICES: static(HARDWARE) if physical else failing(PHYSICAL_DEVICES),
                FLEET_STATUS: (lambda _p: envelope([report(1, CONNECTED, 2)], total_pages=1))
                if fleet
                else failing(FLEET_STATUS),
            }
        )

    def test_full_load(self) -> None:
        """All three endpoints answer: no warnings, and a 60-minute window."""
        getter = self.routes()
        listing = load(getter, NOW)
        self.assertEqual(listing.warnings, [])
        self.assertEqual(listing.devices[0].status, CONNECTED)
        window = next(params for path, params in getter.calls if path == FLEET_STATUS)
        self.assertEqual(
            (window["source"], window["from"], window["to"]),
            ("last_seen", "2026-11-03T02:30:00Z", "2026-11-03T03:30:00Z"),
        )

    def test_fleet_failure_warns(self) -> None:
        """A DEX failure names the endpoint and marks status unknown."""
        listing = load(self.routes(fleet=False), NOW)
        self.assertTrue(any(FLEET_STATUS in warning for warning in listing.warnings))
        self.assertEqual({d.status for d in listing.devices}, {UNKNOWN})

    def test_malformed_fleet_degrades(self) -> None:
        """A DEX report with a bad timestamp warns like a failed fetch, not a failed listing."""
        for label, value in (("missing", None), ("number", 123), ("garbage", "yesterday")):
            bad = report(1, CONNECTED, 2)
            if value is None:
                del bad["timestamp"]
            else:
                bad["timestamp"] = value
            getter = self.routes()
            getter.routes[FLEET_STATUS] = lambda _p, bad=bad: envelope([bad], total_pages=1)
            with self.subTest(timestamp=label):
                listing = load(getter, NOW)
                self.assertTrue(
                    any(
                        FLEET_STATUS in warning and "malformed" in warning
                        for warning in listing.warnings
                    ),
                    listing.warnings,
                )
                self.assertIn("device status is unknown", listing.warnings)
                self.assertEqual({d.status for d in listing.devices}, {UNKNOWN})

    def test_malformed_registration_raises(self) -> None:
        """A bad registrations timestamp still fails the listing."""
        broken = registration("bravo", 1, minutes_ago=1)
        broken["last_seen_at"] = 123
        getter = self.routes()
        getter.routes[REGISTRATIONS] = static([broken])
        with self.assertRaises(DataError):
            load(getter, NOW)

    def test_physical_failure_warns(self) -> None:
        """A physical-devices failure leaves the hardware columns empty."""
        listing = load(self.routes(physical=False), NOW)
        self.assertTrue(any(PHYSICAL_DEVICES in warning for warning in listing.warnings))
        self.assertTrue(all(d.public_ip is None for d in listing.devices))

    def test_registrations_failure_raises(self) -> None:
        """Without registrations there is nothing to list."""
        getter = self.routes()
        getter.routes[REGISTRATIONS] = failing(REGISTRATIONS)
        with self.assertRaises(ApiError):
            load(getter, NOW)

    def test_requests_warp_registrations_only(self) -> None:
        """Browser-extension registrations stay out of the listing."""
        getter = self.routes()
        load(getter, NOW)
        query = next(params for path, params in getter.calls if path == REGISTRATIONS)
        self.assertEqual(query["registration_type"], "warp")

    def test_required_failure_does_not_wait_for_stalls(self) -> None:
        """A failed registrations fetch returns while DEX is still stalled."""
        release = threading.Event()

        def stalled(_params: Mapping[str, str]) -> Json:
            release.wait(10)
            return envelope([], total_pages=1)

        getter = self.routes()
        getter.routes[REGISTRATIONS] = failing(REGISTRATIONS)
        getter.routes[FLEET_STATUS] = stalled
        started = time.monotonic()
        try:
            with self.assertRaises(ApiError):
                load(getter, NOW)
            self.assertLess(time.monotonic() - started, 2)
        finally:
            release.set()


class StrictDataTest(unittest.TestCase):
    """Malformed timestamps fail instead of reading as missing."""

    def test_non_string_last_seen(self) -> None:
        """A numeric last_seen_at is an error, not a never-seen device."""
        broken = registration("bravo", 1, minutes_ago=1)
        broken["last_seen_at"] = 123
        with self.assertRaises(DataError):
            merge([broken], [], latest_reports([]))

    def test_report_without_timestamp(self) -> None:
        """A DEX report with no timestamp is an error, not a silent offline."""
        bare = report(1, CONNECTED, 1)
        del bare["timestamp"]
        with self.assertRaises(DataError):
            latest_reports([bare])
