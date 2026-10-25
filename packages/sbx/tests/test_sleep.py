# Copyright (c) 2026 Bad3r
"""Host sleep phases of sbx against a fake backend."""

import dataclasses
import fcntl
import io
import os
import signal
import unittest
from contextlib import redirect_stderr, redirect_stdout
from typing import TYPE_CHECKING, cast
from unittest import mock

from sbx import cli
from sbx.errors import SbxError
from sbx.sandboxes import Sandboxes
from sbx.sleep import Sleep

from tests.test_core import NOW, FakeBackend, Fixture

if TYPE_CHECKING:
    from sbx.model import Meta


class SleepTest(Fixture):
    """Pause, resume, save, and restore against the sandbox TTL."""

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
        self.attaches = 0
        self.refused = False
        stub = self.scratch / "stubs" / "inactive"
        stub.write_text("#!/bin/sh\nexit 3\n")
        stub.chmod(0o755)
        sleep_patch = mock.patch("sbx.sleep.time.sleep")
        sleep_patch.start()
        self.addCleanup(sleep_patch.stop)

    def connect(self, _slice: bool) -> FakeBackend:  # noqa: FBT001
        """Count connections that may start the daemon."""
        self.connects += 1
        return self.fake

    def attach(self) -> FakeBackend:
        """Count connections that never start the daemon."""
        self.attaches += 1
        if self.refused:
            msg = "Failed to connect socket"
            raise SbxError(msg, code="no-daemon")
        return self.fake

    def phase(self, phase: str, *, daemon: bool = True) -> tuple[list[dict[str, str]], int]:
        """Run one phase with the daemon unit active or not."""
        systemctl = str(self.scratch / "stubs" / ("other" if daemon else "inactive"))
        tools = dataclasses.replace(self.settings.tools, systemctl=systemctl)
        settings = dataclasses.replace(self.settings, tools=tools)
        sandboxes = Sandboxes(settings, self.paths, self.connect, None, lambda: NOW)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as errors:
            actions, code = Sleep(sandboxes, self.state, self.attach, as_json=True).run(phase)
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

    def expire(self, name: str) -> None:
        """Put a sandbox past its TTL."""
        info = self.fake.domains_by_name[f"sbx-{name}"]
        meta = dataclasses.replace(cast("Meta", info.meta), expires=NOW - 1)
        self.fake.domains_by_name[f"sbx-{name}"] = dataclasses.replace(info, meta=meta)

    def test_no_daemon(self) -> None:
        """Pause and save never start a daemon, and a refused connection means none runs."""
        for phase in ("pause", "save"):
            with self.subTest(phase=phase):
                self.assertEqual(self.phase(phase, daemon=False), ([], 0))
        self.assertEqual(self.attaches, 0)
        self.refused = True
        for phase in ("pause", "save"):
            with self.subTest(phase=phase, refused=True):
                self.assertEqual(self.phase(phase), ([], 0))
        self.assertEqual(self.connects, 0)
        self.assertFalse(self.state.exists())

    def test_no_records(self) -> None:
        """Without a record, resume and restore never connect."""
        for phase in ("resume", "restore"):
            with self.subTest(phase=phase):
                self.assertEqual(self.phase(phase), ([], 0))
        self.assertEqual(self.connects + self.attaches, 0)

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

    def test_pause_and_resume_failures_exit_one(self) -> None:
        """A sandbox that fails to pause or resume fails the phase; a stale clock only warns."""
        self.fake.add("c", expires=NOW + 3600)
        self.fake.failing.add("sbx-a")
        _, code = self.phase("pause")
        self.assertEqual(code, 1)
        self.assertIn("warning: a kept running through suspend", self.errors)
        self.assertEqual(self.states(), {"a": "running", "b": "paused", "c": "paused"})
        self.fake.failing = {"sbx-c"}
        _, code = self.phase("resume")
        self.assertEqual(code, 1)
        self.assertIn("warning: c stays paused", self.errors)
        self.fake.failing = set()
        self.fake.suspend("sbx-b")
        self.state.joinpath("paused").write_text("b\n")
        self.fake.unconnected["sbx-b"] = 1
        with mock.patch("sbx.sleep.AGENT_WAIT", 0):
            _, code = self.phase("resume")
        self.assertEqual(code, 0)
        self.assertIn("warning: b keeps a stale clock", self.errors)

    def test_unsynchronized_host_clock(self) -> None:
        """Without NTP sync on the host, guest clocks are left alone."""
        self.phase("pause")
        with mock.patch.dict(os.environ, {"SBX_TEST_NTP": "no"}):
            actions, code = self.phase("resume")
        self.assertEqual(code, 0)
        self.assertEqual([item["action"] for item in actions], ["resumed", "resumed"])
        self.assertIn("not NTP-synchronized", self.errors)
        self.assertEqual(self.fake.synced, [])

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
        self.assertEqual(self.connects, 0)

    def test_save_with_an_unsynced_clock_keeps_expired(self) -> None:
        """Without NTP sync, save saves an expired sandbox instead of destroying it."""
        self.expire("b")
        with mock.patch.dict(os.environ, {"SBX_TEST_NTP": "no"}):
            actions, code = self.phase("save")
        self.assertEqual(code, 0)
        self.assertEqual([item["action"] for item in actions], ["saved", "saved"])
        self.assertIn("expired sandboxes are saved too", self.errors)

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
                    self.assertIn("takes up to 4096M", self.errors)
                    self.assertEqual(self.states(), {"a": "running", "b": "running"})
        self.assertEqual(self.states(), {"a": "shutoff", "b": "shutoff"})

    def test_save_with_nothing_left_ignores_the_floor(self) -> None:
        """A save that only destroys expired sandboxes passes below the floor."""
        self.expire("a")
        self.expire("b")
        self.settings = dataclasses.replace(self.settings, min_free_bytes=1 << 62)
        actions, code = self.phase("save")
        self.assertEqual(code, 0)
        self.assertEqual([item["action"] for item in actions], ["destroyed", "destroyed"])
        self.assertEqual(self.states(), {})
        self.assertEqual(self.record("saved"), [])

    def test_save_past_its_budget_aborts_the_job(self) -> None:
        """A save still running at the budget is aborted, and the guest keeps running."""
        self.fake.before_save = lambda: None
        with mock.patch("sbx.sleep.SAVE_BUDGET", 0):
            _, code = self.phase("save")
        self.assertEqual(code, 1)
        self.assertEqual(self.fake.aborted, ["sbx-a"])
        self.assertIn("ran past 0 s", self.errors)
        self.assertEqual(self.states(), {"a": "running", "b": "running"})

    def test_sigterm_aborts_the_save(self) -> None:
        """SIGTERM from the hook's timeout aborts the running save job."""

        def terminate() -> None:
            os.kill(os.getpid(), signal.SIGTERM)

        self.fake.before_save = terminate
        _, code = self.phase("save")
        self.assertEqual(code, 1)
        self.assertEqual(self.fake.aborted, ["sbx-a"])
        self.assertIn("sbx was stopped", self.errors)
        self.assertIs(signal.getsignal(signal.SIGTERM), signal.SIG_DFL)

    def test_held_lock(self) -> None:
        """A lock another command keeps fails each phase after a bounded wait."""
        self.state.mkdir(parents=True)
        self.state.joinpath("paused").write_text("a\n")
        with self.paths.lock.open("a") as held, mock.patch("sbx.sleep.LOCK_WAIT", 0):
            fcntl.flock(held, fcntl.LOCK_EX)
            for phase in ("pause", "resume", "save"):
                with self.subTest(phase=phase):
                    self.assertEqual(self.phase(phase), ([], 1))
                    self.assertIn(f"{phase} stopped: another sbx command held", self.errors)
        self.assertEqual(self.states(), {"a": "running", "b": "running"})
        self.assertEqual(self.record("paused"), ["a"])

    def test_restore_leaves_expiry_to_gc(self) -> None:
        """Restore brings back every saved sandbox, even one past its TTL."""
        self.phase("save")
        self.expire("b")
        actions, code = self.phase("restore")
        self.assertEqual(code, 0)
        self.assertEqual(
            [item["action"] for item in actions], ["restored", "restored", "synced", "synced"]
        )
        self.assertEqual(self.states(), {"a": "running", "b": "running"})
        self.assertFalse((self.state / "saved").exists())

    def test_restore_waits_for_a_running_save(self) -> None:
        """A recorded sandbox still saving is restored once its job ends."""
        self.state.mkdir(parents=True)
        self.state.joinpath("saved").write_text("a\n")
        self.fake.jobs["sbx-a"] = 3
        actions, code = self.phase("restore")
        self.assertEqual(code, 0)
        self.assertIn({"sandbox": "a", "action": "restored"}, actions)
        self.assertFalse((self.state / "saved").exists())

    def test_restore_keeps_unresolved_names(self) -> None:
        """A save that outlasts the wait, or a failed restore, stays recorded and exits 1."""
        self.phase("save")
        self.fake.add("c", expires=NOW + 3600)
        self.state.joinpath("saved").write_text("a\nb\nc\n")
        self.fake.jobs["sbx-c"] = 1000
        self.fake.failing.add("sbx-a")
        with mock.patch("sbx.sleep.JOB_WAIT", 0):
            actions, code = self.phase("restore")
        self.assertEqual(code, 1)
        self.assertIn({"sandbox": "b", "action": "restored"}, actions)
        self.assertIn("error: a stays saved", self.errors)
        self.assertIn("error: c is still saving", self.errors)
        self.assertEqual(self.record("saved"), ["a", "c"])

    def test_restore_refuses_a_foreign_emulator(self) -> None:
        """A sandbox whose QEMU is not this sbx-qemu stays saved and is not retried."""
        self.phase("save")
        self.fake.domains_by_name["sbx-a"] = dataclasses.replace(
            self.fake.domains_by_name["sbx-a"], emulator="/nix/store/qemu/bin/qemu-system-x86_64"
        )
        actions, code = self.phase("restore")
        self.assertEqual(code, 1)
        self.assertNotIn({"sandbox": "a", "action": "restored"}, actions)
        self.assertIn({"sandbox": "b", "action": "restored"}, actions)
        self.assertIn("is not an sbx-qemu", self.errors)
        self.assertIn("run `sbx destroy a`", self.errors)
        self.assertEqual(self.states()["a"], "shutoff")
        self.assertFalse((self.state / "saved").exists())

    def test_restore_accepts_an_earlier_wrapper_build(self) -> None:
        """A sandbox saved under an sbx-qemu from an earlier switch is restored."""
        self.phase("save")
        self.fake.domains_by_name["sbx-a"] = dataclasses.replace(
            self.fake.domains_by_name["sbx-a"],
            emulator="/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-sbx-qemu",
        )
        actions, code = self.phase("restore")
        self.assertEqual(code, 0)
        self.assertIn({"sandbox": "a", "action": "restored"}, actions)

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
