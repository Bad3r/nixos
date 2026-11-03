# Copyright (c) 2026 Bad3r
"""Command line arguments, output, and exit codes."""

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import TYPE_CHECKING

from warp_devices.api import ApiError, Json
from warp_devices.cli import BROKEN_PIPE_EXIT, LOOKUP_EXIT, USAGE_EXIT, main
from warp_devices.devices import FLEET_STATUS, PHYSICAL_DEVICES, REGISTRATIONS

from tests.fixtures import (
    NOW,
    FakeGetter,
    Handler,
    envelope,
    hardware,
    pin_utc,
    registration,
    report,
    static,
)

if TYPE_CHECKING:
    from collections.abc import Mapping

REGS = [
    registration("songbird", 9, minutes_ago=1, user="svc@example.com"),
    registration("laptop", 4, minutes_ago=121),
]
HARDWARE = [hardware(9, name="songbird"), hardware(4, name="laptop", os_name="windows")]


def fleet(params: Mapping[str, str]) -> Json:
    """Answer the last_seen window with songbird connected, raw history with two reports."""
    if params.get("source") == "raw":
        return envelope(
            [report(4, "connected", 30), report(4, "connecting", 10)],
            total_pages=1,
        )
    return envelope([report(9, "connected", 2)], total_pages=1)


def getter() -> FakeGetter:
    """Return a getter answering every endpoint."""
    return FakeGetter(
        {REGISTRATIONS: static(REGS), PHYSICAL_DEVICES: static(HARDWARE), FLEET_STATUS: fleet}
    )


def run(*argv: str, client: FakeGetter | None = None) -> tuple[int, str, str]:
    """Run main and capture its exit code, stdout, and stderr."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = main(list(argv), client=client or getter(), clock=lambda: NOW)
        except SystemExit as stop:
            code = int(stop.code or 0)
    return code, out.getvalue(), err.getvalue()


class ListTest(unittest.TestCase):
    """The default command prints the table or JSON."""

    def setUp(self) -> None:
        """Pin local time to UTC."""
        pin_utc()

    def test_default_command(self) -> None:
        """No command runs list without IPv6 or user columns."""
        code, out, err = run()
        self.assertEqual((code, err), (0, ""))
        lines = out.splitlines()
        self.assertEqual(
            lines[0].split(), ["NAME", "STATUS", "MESH_IPV4", "PUBLIC_IP", "OS", "LAST_SEEN"]
        )
        self.assertEqual(lines[1].split()[:3], ["songbird", "connected", "100.96.0.9"])
        self.assertIn("2 hours ago", lines[2])
        self.assertNotIn("\033[", out)

    def test_optional_columns(self) -> None:
        """--ipv6 and --user add their columns in place."""
        _, out, _ = run("--ipv6", "--user")
        self.assertEqual(
            out.splitlines()[0].split(),
            ["NAME", "STATUS", "MESH_IPV4", "MESH_IPV6", "PUBLIC_IP", "OS", "USER", "LAST_SEEN"],
        )
        self.assertIn("svc@example.com", out)

    def test_json(self) -> None:
        """--json prints every field and the warnings list."""
        code, out, _ = run("list", "--json")
        payload = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(payload["warnings"], [])
        self.assertEqual(payload["devices"][0]["mesh_ipv6"], "2001:db8::9")
        self.assertEqual(payload["devices"][1]["status"], "offline")

    def test_forced_color(self) -> None:
        """--color colors even a non-terminal."""
        _, out, _ = run("--color")
        self.assertIn("\033[1;32mconnected", out)

    def test_degraded_warns(self) -> None:
        """A DEX failure still lists, with a warning on stderr."""
        client = getter()

        def broken(_params: Mapping[str, str]) -> Json:
            raise ApiError(FLEET_STATUS, "HTTP 503 after 5 attempts")

        client.routes[FLEET_STATUS] = broken
        code, out, err = run(client=client)
        self.assertEqual(code, 0)
        self.assertIn("warning: GET dex/fleet-status/devices failed", err)
        self.assertIn("unknown", out)

    def test_malformed_dex_degrades(self) -> None:
        """A DEX report with a bad timestamp still lists, exits 0, and warns."""
        client = getter()
        bad = report(9, "connected", 2)
        bad["timestamp"] = "not a time"
        client.routes[FLEET_STATUS] = lambda _params: envelope([bad], total_pages=1)
        code, out, err = run(client=client)
        self.assertEqual(code, 0)
        self.assertIn("warning: GET dex/fleet-status/devices returned malformed data", err)
        self.assertIn("warning: STATUS shows unknown", err)
        self.assertEqual(out.splitlines()[1].split()[:2], ["songbird", "unknown"])

    def test_malformed_registration_fails(self) -> None:
        """A bad registrations timestamp exits 1 instead of guessing."""
        client = getter()
        broken = registration("songbird", 9, minutes_ago=1)
        broken["last_seen_at"] = 123
        client.routes[REGISTRATIONS] = static([broken])
        code, out, err = run(client=client)
        self.assertEqual((code, out), (1, ""))
        self.assertIn("unexpected data from Cloudflare", err)

    def test_stderr_controls_are_escaped(self) -> None:
        """API text in warnings and errors reaches stderr with its controls escaped."""
        client = getter()

        def hostile(path: str) -> Handler:
            def handler(_params: Mapping[str, str]) -> Json:
                raise ApiError(path, "Bad\x1b]0;pwned\x07\x9b")

            return handler

        client.routes[FLEET_STATUS] = hostile(FLEET_STATUS)
        code, _, err = run(client=client)
        self.assertEqual(code, 0)
        self.assertIn(r"warning: GET dex/fleet-status/devices failed: Bad\x1b]0;pwned\x07\x9b", err)
        client.routes[REGISTRATIONS] = hostile(REGISTRATIONS)
        code, _, err = run(client=client)
        self.assertEqual(code, 1)
        self.assertIn(r"GET devices/registrations failed: Bad\x1b]0;pwned\x07\x9b", err)
        self.assertNotRegex(err, r"[\x1b\x07\x9b]")

    def test_forbidden_hint(self) -> None:
        """A 403 on registrations exits 1 and names the needed permissions."""
        client = getter()

        def forbidden(_params: Mapping[str, str]) -> Json:
            raise ApiError(REGISTRATIONS, "Authentication error", status=403)

        client.routes[REGISTRATIONS] = forbidden
        code, _, err = run(client=client)
        self.assertEqual(code, 1)
        self.assertIn("Zero Trust Read and DEX Read", err)


class HistoryTest(unittest.TestCase):
    """history resolves a device and prints its reports."""

    def setUp(self) -> None:
        """Pin local time to UTC."""
        pin_utc()

    def test_table(self) -> None:
        """Reports print oldest first with the gap between them."""
        code, out, err = run("history", "LAPTOP", "--hours", "2")
        self.assertEqual(code, 0)
        self.assertIn("laptop: past 2 hours, 2 of 2 reports shown", err)
        lines = out.splitlines()
        self.assertEqual(lines[1].split()[4:6], ["-", "connected"])
        self.assertEqual(lines[2].split()[4:6], ["20m", "connecting"])

    def test_window_and_device(self) -> None:
        """The raw query carries the device ID and the hour window."""
        client = getter()
        run("history", "laptop", "--hours", "3", client=client)
        raw = next(p for path, p in client.calls if path == FLEET_STATUS and p["source"] == "raw")
        self.assertEqual(
            (raw["device_id"], raw["from"], raw["to"]),
            ("dev-4", "2026-11-03T00:30:00Z", "2026-11-03T03:30:00Z"),
        )

    def test_json(self) -> None:
        """--json prints the device and its reports."""
        _, out, _ = run("history", "laptop", "--json")
        payload = json.loads(out)
        self.assertEqual(payload["device"], {"id": "dev-4", "name": "laptop"})
        self.assertEqual([r["status"] for r in payload["reports"]], ["connected", "connecting"])

    def test_name_line_is_escaped(self) -> None:
        """The device name on the summary line has its controls escaped."""
        client = getter()
        client.routes[PHYSICAL_DEVICES] = static([hardware(4, name="lap\x1b[2Jtop")])
        code, _, err = run("history", "dev-4", client=client)
        self.assertEqual(code, 0)
        self.assertIn(r"lap\x1b[2Jtop: past 24 hours", err)
        self.assertNotIn("\x1b", err)

    def test_unknown_device(self) -> None:
        """An unknown device exits 3."""
        code, _, err = run("history", "ghost")
        self.assertEqual(code, LOOKUP_EXIT)
        self.assertIn("no device named 'ghost'", err)

    def test_hours_bounds(self) -> None:
        """Hours outside 1 to 168 are a usage error."""
        for value in ("0", "169", "x"):
            with self.subTest(value=value):
                self.assertEqual(run("history", "laptop", "--hours", value)[0], USAGE_EXIT)


class InvocationTest(unittest.TestCase):
    """Usage errors, help, credentials, and broken pipes."""

    def test_usage_error(self) -> None:
        """An unknown flag exits 2."""
        self.assertEqual(run("--bogus")[0], USAGE_EXIT)

    def test_help(self) -> None:
        """--help names both commands and exits 0."""
        code, out, _ = run("--help")
        self.assertEqual(code, 0)
        self.assertIn("history", out)

    def test_missing_credential(self) -> None:
        """A missing token file names its path and where it comes from."""
        with tempfile.TemporaryDirectory() as directory:
            account = Path(directory) / "account-id"
            account.write_text("acct\n")
            missing = Path(directory) / "api-token"
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = main(["--account-id-file", str(account), "--token-file", str(missing)])
        self.assertEqual(code, 1)
        self.assertIn(str(missing), err.getvalue())
        self.assertIn("zero_trust_read_api_token", err.getvalue())

    def test_empty_credential(self) -> None:
        """An empty credential file is an error, not an empty token."""
        with tempfile.TemporaryDirectory() as directory:
            empty = Path(directory) / "empty"
            empty.write_text("\n")
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code = main(["--account-id-file", str(empty), "--token-file", str(empty)])
        self.assertEqual(code, 1)
        self.assertIn("is empty", err.getvalue())

    def test_multiline_token_is_rejected_unseen(self) -> None:
        """A token file with a second line fails without printing either line."""
        with tempfile.TemporaryDirectory() as directory:
            account = Path(directory) / "account-id"
            account.write_text("acct\n")
            token = Path(directory) / "api-token"
            token.write_text("SECRET-TOKEN\n# a comment\n")
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code = main(["--account-id-file", str(account), "--token-file", str(token)])
        self.assertEqual(code, 1)
        self.assertNotIn("SECRET-TOKEN", err.getvalue())
        self.assertIn(str(token), err.getvalue())

    def test_non_utf8_credential(self) -> None:
        """A binary credential file is a credential error, not bad Cloudflare data."""
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "binary"
            binary.write_bytes(b"\xff\xfe")
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code = main(["--account-id-file", str(binary), "--token-file", str(binary)])
        self.assertEqual(code, 1)
        self.assertIn("not UTF-8", err.getvalue())

    def test_flag_before_command(self) -> None:
        """A valueless flag before the command still runs that command."""
        pin_utc()
        code, out, _ = run("--no-color", "history", "laptop")
        self.assertEqual(code, 0)
        self.assertIn("connecting", out)

    def test_value_flag_before_command(self) -> None:
        """A flag's value before the command is not mistaken for the device or a list argument."""
        pin_utc()
        for flags in (
            ["--token-file", "token"],
            ["--token-file=token"],
            ["--account-id-file", "acct", "--no-color"],
            ["--token", "token"],
            ["--hours", "2"],
        ):
            with self.subTest(flags=flags):
                code, out, err = run(*flags, "history", "laptop")
                self.assertEqual((code, err.count("usage")), (0, 0), err)
                self.assertIn("connecting", out)

    def test_broken_pipe(self) -> None:
        """Output into a pipe whose reader closed exits 141 with nothing on stderr."""
        script = """
import sys
sys.path.insert(0, sys.argv[1])
from tests.test_cli import getter, NOW
from warp_devices.cli import main
sys.exit(main([], client=getter(), clock=lambda: NOW))
"""
        read_end, write_end = os.pipe()
        os.close(read_end)
        try:
            done = subprocess.run(
                [sys.executable, "-I", "-c", script, str(Path(__file__).resolve().parents[1])],
                stdout=write_end,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            os.close(write_end)
        self.assertEqual((done.returncode, done.stderr), (BROKEN_PIPE_EXIT, b""))
