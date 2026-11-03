# Copyright (c) 2026 Bad3r
"""Device lookup and the history change filter."""

import unittest
from typing import TYPE_CHECKING

from warp_devices.history import LookupFailedError, entries, resolve, to_report

from tests.fixtures import dex_stamp

if TYPE_CHECKING:
    from warp_devices.api import Json

PHYSICAL: list[Json] = [
    {"id": "dev-1", "name": "cyb-laptop"},
    {"id": "dev-2", "name": "twin"},
    {"id": "dev-3", "name": "TWIN"},
]


def raw(
    minutes_ago: float, status: str = "connected", *, colo: str = "DME", isp: str = "203.0.113.9"
) -> Json:
    """Return one raw DEX report."""
    return {
        "timestamp": dex_stamp(minutes_ago),
        "status": status,
        "colo": colo,
        "ispIpv4": {"address": isp},
        "deviceIpv4": {"address": "192.0.2.10"},
        "gatewayIpv4": {"address": "192.0.2.1"},
        "handshakeLatencyMs": 21,
        "estimatedLossPct": 0.5,
    }


class ResolveTest(unittest.TestCase):
    """Names match case-insensitively; IDs match exactly; ambiguity is an error."""

    def test_by_name(self) -> None:
        """A name matches regardless of case."""
        self.assertEqual(resolve(PHYSICAL, "CYB-Laptop")["id"], "dev-1")

    def test_by_id(self) -> None:
        """An ID picks one of two devices sharing a name."""
        self.assertEqual(resolve(PHYSICAL, "dev-3")["name"], "TWIN")

    def test_ambiguous(self) -> None:
        """Two devices with one name list both IDs."""
        with self.assertRaisesRegex(LookupFailedError, "dev-2, dev-3"):
            resolve(PHYSICAL, "twin")

    def test_missing(self) -> None:
        """An unknown name says so."""
        with self.assertRaisesRegex(LookupFailedError, "no device named"):
            resolve(PHYSICAL, "ghost")


class EntriesTest(unittest.TestCase):
    """The filter keeps ends, changes, and gaps, in time order."""

    def test_filter(self) -> None:
        """Steady reports two minutes apart collapse; changes and a long gap stay."""
        records = [
            raw(60),
            raw(58),
            raw(56),
            raw(54, colo="OTP"),
            raw(52, colo="OTP"),
            raw(30, colo="OTP"),
            raw(28, "connecting", colo="JED"),
            raw(26, "connecting", colo="JED", isp="198.51.100.4"),
            raw(24, "connecting", colo="JED", isp="198.51.100.4"),
        ]
        reports = [to_report(record) for record in reversed(records)]
        kept = entries(reports, show_all=False)
        self.assertEqual(
            [(e.report.colo, e.report.status, e.gap_seconds) for e in kept],
            [
                ("DME", "connected", None),
                ("OTP", "connected", 120.0),
                ("OTP", "connected", 1320.0),
                ("JED", "connecting", 120.0),
                ("JED", "connecting", 120.0),
                ("JED", "connecting", 120.0),
            ],
        )
        self.assertEqual(len(entries(reports, show_all=True)), len(records))

    def test_report_fields(self) -> None:
        """A raw report keeps the addresses and measurements history shows."""
        report = to_report(raw(1))
        self.assertEqual(
            (
                report.isp_ipv4,
                report.lan_ipv4,
                report.gateway_ipv4,
                report.handshake_ms,
                report.loss_pct,
            ),
            ("203.0.113.9", "192.0.2.10", "192.0.2.1", 21.0, 0.5),
        )

    def test_report_without_timestamp(self) -> None:
        """A report without a timestamp is malformed data."""
        with self.assertRaises(ValueError):
            to_report({"status": "connected"})
