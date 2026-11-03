# Copyright (c) 2026 Bad3r
"""Timestamp parsing and age wording."""

import os
import time
import unittest
from datetime import UTC, datetime, timedelta

from warp_devices.timefmt import DataError, ago, local_clock, parse, parse_optional, span

from tests.fixtures import NOW, pin_utc


class ParseTest(unittest.TestCase):
    """Every timestamp form Cloudflare sends parses to the same aware time."""

    def test_forms(self) -> None:
        """Z, a five-digit fraction, and DEX's space and +00 form."""
        expected = datetime(2026, 11, 3, 1, 24, 45, 841250, tzinfo=UTC)
        for text in (
            "2026-11-03T01:24:45.84125Z",
            "2026-11-03 01:24:45.84125+00",
            "2026-11-03T01:24:45.84125+00:00",
        ):
            with self.subTest(text=text):
                self.assertEqual(parse(text), expected)

    def test_whole_seconds(self) -> None:
        """A timestamp without a fraction parses."""
        self.assertEqual(
            parse("2026-10-27T13:39:24Z"), datetime(2026, 10, 27, 13, 39, 24, tzinfo=UTC)
        )

    def test_malformed(self) -> None:
        """A malformed value raises instead of reading as missing."""
        with self.assertRaisesRegex(DataError, "unrecognized timestamp"):
            parse("yesterday")
        with self.assertRaises(DataError):
            parse_optional(17)

    def test_absent(self) -> None:
        """Absent and empty values are None."""
        self.assertIsNone(parse_optional(None))
        self.assertIsNone(parse_optional(""))


class AgoTest(unittest.TestCase):
    """Ages read naturally at every boundary."""

    def setUp(self) -> None:
        """Pin local time to UTC."""
        pin_utc()

    def test_boundaries(self) -> None:
        """Seconds, minutes, hours, and days, singular and plural."""
        cases = {
            timedelta(seconds=-5): "just now",
            timedelta(seconds=59): "just now",
            timedelta(seconds=60): "1 min ago",
            timedelta(minutes=12): "12 mins ago",
            timedelta(minutes=59, seconds=59): "59 mins ago",
            timedelta(hours=1): "1 hour ago",
            timedelta(hours=23, minutes=59): "23 hours ago",
            timedelta(days=1): "Mon Nov 2, 03:30 (1 day ago)",
            timedelta(days=7, hours=2): "Tue Oct 27, 01:30 (7 days ago)",
        }
        for delta, wording in cases.items():
            with self.subTest(delta=delta):
                self.assertEqual(ago(NOW - delta, NOW), wording)

    def test_year_shown_across_local_new_year(self) -> None:
        """A moment in another local year than now shows the year; the same year does not."""
        new_year = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
        cases = [
            (datetime(2026, 1, 1, 0, 0, tzinfo=UTC), new_year, "Thu Jan 1, 00:00 (1 day ago)"),
            (
                datetime(2025, 12, 31, 23, 59, tzinfo=UTC),
                new_year,
                "Wed Dec 31 2025, 23:59 (1 day ago)",
            ),
            (NOW - timedelta(days=372), NOW, "Mon Oct 27 2025, 03:30 (372 days ago)"),
        ]
        for moment, now, wording in cases:
            with self.subTest(moment=moment):
                self.assertEqual(ago(moment, now), wording)

    def test_year_follows_the_local_zone(self) -> None:
        """Past local midnight on New Year, no year shows while UTC is still in the old one."""
        self.addCleanup(pin_utc)
        os.environ["TZ"] = "<+09>-9"
        time.tzset()
        moment = datetime(2025, 12, 31, 16, 0, tzinfo=UTC)
        now = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
        self.assertEqual(ago(moment, now), "Thu Jan 1, 01:00 (1 day ago)")


class FormatTest(unittest.TestCase):
    """Durations and clock times for the history table."""

    def test_span(self) -> None:
        """Compact durations at each unit."""
        self.assertEqual(
            [span(s) for s in (0, 59, 60, 3599, 3600, 21600, 86400 + 3 * 3600)],
            ["0s", "59s", "1m", "59m", "1h 0m", "6h 0m", "1d 3h"],
        )

    def test_local_clock(self) -> None:
        """A local clock time pads the day."""
        pin_utc()
        self.assertEqual(
            local_clock(datetime(2026, 11, 2, 8, 50, 8, tzinfo=UTC)), "Mon Nov  2 08:50:08"
        )
