# Copyright (c) 2026 Bad3r
"""Host sleep phases of sbx against a fake backend."""

import dataclasses
import fcntl
import io
import unittest
from contextlib import redirect_stderr, redirect_stdout
from typing import cast
from unittest import mock

from sbx import cli
from sbx.core import Meta, Sandboxes, SbxError
from sbx.sleep import Sleep

from tests.test_core import NOW, FakeBackend, Fixture


class SleepTest(Fixture):
    """pause, resume, save, and restore against the sandbox TTL."""

    def setUp(self) -> None:
        """Lay out the core fixture with two running sandboxes."""
        super().setUp()
        self.fake = self.backend
        self.state = self.scratch / "run" / "sbx"
        self.paths.config.mkdir(parents=True)
        for name in ("a", "b"):
            self.paths.sandbox(name).mkdir(parents=True)
        self.fake.add("a", expires=NOW + 3600)
        self.fake.add("b", expires=NOW + 3600)
        self.connects = 0
        sleep_patch = mock.patch("sbx.sleep.time.sleep")
        sleep_patch.start()
        self.addCleanup(sleep_patch.stop)

    def connect(self, _slice: bool) -> FakeBackend:  # noqa: FBT001
        """Count connections to the fake daemon."""
        self.connects += 1
        return self.fake

    def phase(self, phase: str, *, daemon: bool = True) -> tuple[list[dict[str, str]], int]:
        """Run one phase with the daemon unit active or not."""
        systemctl = "other" if daemon else "inactive"
        stub = self.scratch / "stubs" / "inactive"
        stub.write_text("#!/bin/sh\nexit 3\n")
        stub.chmod(0o755)
        tools = dataclasses.replace(
            self.settings.tools, systemctl=str(self.scratch / "stubs" / systemctl)
        )
        settings = dataclasses.replace(self.settings, tools=tools)
        sandboxes = Sandboxes(settings, self.paths, self.connect, None, lambda: NOW)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as errors:
            actions, code = Sleep(sandboxes, self.state, as_json=True).run(phase)
        self.errors = errors.getvalue()
        return actions, code

    def states(self) -> dict[str, str]:
        """Map each sandbox to its fake state."""
        return {
            name.removeprefix("sbx-"): info.state
            for name, info in self.fake.domains_by_name.items()
        }

    def record(self, name: str) -> list[str]:
        """Read one record, empty when absent."""
        path = self.state / name
        return path.read_text().splitlines() if path.exists() else []

    def test_inactive_daemon(self) -> None:
        """Without the daemon unit, pause and save neither connect nor record."""
        for phase in ("pause", "save"):
            with self.subTest(phase=phase):
                self.assertEqual(self.phase(phase, daemon=False), ([], 0))
        self.assertEqual(self.connects, 0)
        self.assertFalse(self.state.exists())

    def test_no_records(self) -> None:
        """Without a record, resume and restore never connect."""
        for phase in ("resume", "restore"):
            with self.subTest(phase=phase):
                self.assertEqual(self.phase(phase), ([], 0))
        self.assertEqual(self.connects, 0)

    def test_suspend_cycle(self) -> None:
        """Pause records running sandboxes; resume brings back only those and syncs clocks."""
        self.fake.suspend("sbx-b")
        self.fake.add("c", expires=NOW + 3600, active=False, managed_save=True)
        actions, code = self.phase("pause")
        self.assertEqual((actions, code), ([{"sandbox": "a", "action": "paused"}], 0))
        self.assertEqual(self.record("paused"), ["a"])
        self.fake.unconnected["sbx-a"] = 2
        actions, code = self.phase("resume")
        self.assertEqual(code, 0)
        self.assertEqual([item["action"] for item in actions], ["resumed", "synced"])
        self.assertEqual(self.states(), {"a": "running", "b": "paused", "c": "shutoff"})
        self.assertEqual(self.fake.synced, ["sbx-a"])
        self.assertFalse((self.state / "paused").exists())

    def test_pause_and_resume_failures_exit_zero(self) -> None:
        """A sandbox that fails to pause or resume only warns."""
        self.fake.add("c", expires=NOW + 3600)
        self.fake.failing.add("sbx-a")
        _, code = self.phase("pause")
        self.assertEqual(code, 0)
        self.assertIn("warning: a kept running through suspend", self.errors)
        self.assertEqual(self.states(), {"a": "running", "b": "paused", "c": "paused"})
        self.fake.failing = {"sbx-c"}
        self.fake.unconnected["sbx-b"] = 1
        with mock.patch("sbx.sleep.AGENT_WAIT", 0):
            _, code = self.phase("resume")
        self.assertEqual(code, 0)
        self.assertIn("warning: c stays paused", self.errors)
        self.assertIn("warning: b keeps a stale clock", self.errors)

    def test_save_destroys_expired_and_saves_the_rest(self) -> None:
        """Save removes sandboxes past their TTL, then saves the active ones."""
        self.paths.sandbox("old").mkdir()
        self.fake.add("old", expires=NOW)
        self.fake.add("off", expires=NOW + 3600, active=False)
        actions, code = self.phase("save")
        self.assertEqual(code, 0)
        self.assertEqual(
            actions,
            [
                {"sandbox": "old", "action": "destroyed"},
                {"sandbox": "a", "action": "saved"},
                {"sandbox": "b", "action": "saved"},
            ],
        )
        self.assertEqual(self.states(), {"a": "shutoff", "b": "shutoff", "off": "shutoff"})
        self.assertFalse(self.paths.sandbox("old").exists())
        self.assertEqual(self.record("saved"), ["a", "b"])

    def test_failed_save_exits_one(self) -> None:
        """The first failed save stops the phase, and the record keeps it for restore."""
        self.fake.failing.add("sbx-a")
        actions, code = self.phase("save")
        self.assertEqual((actions, code), ([], 1))
        self.assertIn("error: save stopped: a failed to save", self.errors)
        self.assertEqual(self.states(), {"a": "running", "b": "running"})
        self.assertEqual(self.record("saved"), ["a"])

    def test_save_keeps_the_free_space_floor(self) -> None:
        """Save refuses before saving anything when the images could pass the floor."""
        self.settings = dataclasses.replace(self.settings, min_free_bytes=1 << 30)
        # Two sandboxes of 2048M each need 4G of save images.
        need = 4 << 30
        for free, expected in ((need + (1 << 30) - 1, 1), (need + (1 << 30), 0)):
            stats = mock.Mock(f_bavail=free, f_frsize=1)
            with self.subTest(free=free), mock.patch("sbx.sleep.os.statvfs", return_value=stats):
                _, code = self.phase("save")
                self.assertEqual(code, expected)
                if expected:
                    self.assertIn("4096M", self.errors)
                    self.assertEqual(self.states(), {"a": "running", "b": "running"})
        self.assertEqual(self.states(), {"a": "shutoff", "b": "shutoff"})

    def test_held_lock(self) -> None:
        """A lock another command keeps fails save and restore, and only warns for pause."""
        with self.paths.lock.open("a") as held, mock.patch("sbx.sleep.LOCK_WAIT", 0):
            fcntl.flock(held, fcntl.LOCK_EX)
            self.assertEqual(self.phase("pause"), ([], 0))
            self.assertIn("warning: pause stopped: another sbx command held", self.errors)
            self.assertEqual(self.phase("save"), ([], 1))
            self.assertIn("error: save stopped: another sbx command held", self.errors)
        self.assertEqual(self.states(), {"a": "running", "b": "running"})

    def test_restore_honours_ttl(self) -> None:
        """Restore brings back saved sandboxes within TTL and destroys the expired ones."""
        self.phase("save")
        saved = self.fake.domains_by_name["sbx-b"]
        expired = dataclasses.replace(cast("Meta", saved.meta), expires=NOW - 1)
        self.fake.domains_by_name["sbx-b"] = dataclasses.replace(saved, meta=expired)
        actions, code = self.phase("restore")
        self.assertEqual(code, 0)
        self.assertEqual(
            actions,
            [
                {"sandbox": "b", "action": "destroyed"},
                {"sandbox": "a", "action": "restored"},
                {"sandbox": "a", "action": "synced"},
            ],
        )
        self.assertEqual(self.states(), {"a": "running"})
        self.assertFalse(self.paths.sandbox("b").exists())
        self.assertFalse((self.state / "saved").exists())

    def test_failed_restore_exits_one(self) -> None:
        """A sandbox that stays saved fails restore, and the others still come back."""
        self.phase("save")
        self.fake.failing.add("sbx-a")
        actions, code = self.phase("restore")
        self.assertEqual(code, 1)
        self.assertIn({"sandbox": "b", "action": "restored"}, actions)
        self.assertIn("error: a stays saved", self.errors)

    def test_paused_then_saved_comes_back_running(self) -> None:
        """A sandbox paused for suspend and saved for hibernation is restored, then resumed."""
        self.phase("pause")
        self.phase("save")
        self.assertEqual(self.states(), {"a": "shutoff", "b": "shutoff"})
        self.phase("restore")
        self.assertEqual(self.states(), {"a": "paused", "b": "paused"})
        self.phase("resume")
        self.assertEqual(self.states(), {"a": "running", "b": "running"})
        self.assertEqual(sorted(self.fake.synced), ["sbx-a", "sbx-b"])

    def test_cli(self) -> None:
        """`sbx sleep` takes only the four phases."""
        args = cli.build_parser().parse_args(["sleep", "pause", "--json"])
        self.assertEqual((args.verb, args.phase, args.json), ("sleep", "pause", True))
        with self.assertRaises(SbxError):
            cli.build_parser().parse_args(["sleep", "wake"])


if __name__ == "__main__":
    unittest.main()
