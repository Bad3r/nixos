# Copyright (c) 2026 Bad3r
"""The capacity wait queue of create against the core tests' fake backend."""

import dataclasses
import json
import os
import signal
import subprocess
import threading
import time
import unittest
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast
from unittest import mock

from sbx import admission, errors, waitqueue
from sbx.errors import SbxError
from sbx.model import Request
from sbx.sandboxes import Sandboxes

from tests.test_core import NOW, Fixture

if TYPE_CHECKING:
    from collections.abc import Callable


def wait_until(predicate: Callable[[], bool], timeout: float = 10) -> None:
    """Poll until `predicate` holds, failing after `timeout` seconds."""
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() > deadline:
            msg = "condition never held"
            raise AssertionError(msg)
        time.sleep(0.02)


class WaitQueueTest(Fixture):
    """FIFO admission, refusals, and ticket cleanup."""

    def setUp(self) -> None:
        """Poll fast and fill the running ceiling with three sandboxes of other sessions."""
        super().setUp()
        poll = mock.patch.object(admission, "WAIT_POLL", 0.05)
        poll.start()
        self.addCleanup(poll.stop)
        for index in range(3):
            self.backend.add(f"r{index}", expires=NOW + 1800, session="codex:other")
        self.results: dict[str, Any] = {}

    def wait_request(self, name: str, wait: float = 10, memory: int = 2048) -> Request:
        """Return a request that queues up to `wait` seconds."""
        return Request("nixos", name, "none", memory, 2, 3600, wait)

    def start(self, name: str, wait: float = 10, memory: int = 2048) -> threading.Thread:
        """Create `name` with a wait on its own thread; the result or error lands in results."""

        def create() -> None:
            try:
                self.results[name] = self.sandboxes().create(self.wait_request(name, wait, memory))
            except SbxError as error:
                self.results[name] = error

        thread = threading.Thread(target=create)
        thread.start()
        self.addCleanup(thread.join, 15)
        return thread

    def queued(self) -> list[str]:
        """Return the queued names in order."""
        return [ticket.name for ticket in waitqueue.live(self.paths.queue)]

    def free(self, domain: str) -> None:
        """Remove a running sandbox as destroy would, under the state lock."""
        with self.sandboxes().locked():
            self.backend.remove(f"sbx-{domain}")

    def test_over_limit_names_holders_and_retry(self) -> None:
        """A create without a wait fails at once, naming holders and the --wait retry."""
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request())
        error = refused.exception
        self.assertEqual(error.code, "over-limit")
        self.assertIn("r0 (codex:other, 30m left)", str(error))
        self.assertIn("--wait 30m", str(error))
        self.assertIn("sbx destroy --mine", str(error))
        document = errors.error_document(error)
        self.assertEqual(document["retry"], {"wait": "30m"})
        self.assertEqual(
            document["holders"][0],  # pyright: ignore[reportIndexIssue]
            {"name": "r0", "session": "codex:other", "memory_mib": 2048, "ttl_left": 1800},
        )
        self.assertFalse(self.paths.queue.exists())

    def test_never_fitting_requests_fail_at_once(self) -> None:
        """A request above a per-sandbox ceiling never queues."""
        with self.assertRaises(SbxError) as refused:
            self.request(memory="8G", wait="30m")
        self.assertEqual(refused.exception.code, "over-limit")
        began = time.monotonic()
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.wait_request("t1", memory=8192))
        self.assertEqual(refused.exception.code, "over-limit")
        self.assertLess(time.monotonic() - began, 1)
        self.assertEqual(self.queued(), [])

    def test_wait_timeout(self) -> None:
        """A wait that runs out fails with wait-timeout and leaves no ticket."""
        began = time.monotonic()
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.wait_request("t1", wait=0.3))
        self.assertGreaterEqual(time.monotonic() - began, 0.3)
        self.assertEqual(refused.exception.code, "wait-timeout")
        self.assertEqual(len(refused.exception.details["holders"]), 3)  # pyright: ignore[reportArgumentType]
        self.assertNotIn("retry", refused.exception.details)
        self.assertEqual(self.queued(), [])
        messages = [call.args[0] for call in self.journal_record.call_args_list]
        self.assertTrue(any("t1 queues for capacity" in message for message in messages))

    def test_late_waiter_never_starts(self) -> None:
        """A waiter that wakes past its deadline to free capacity times out instead."""
        sleep = time.sleep

        def oversleep(seconds: float) -> None:
            self.backend.domains_by_name.pop("sbx-r0", None)
            sleep(seconds + 0.5)

        with (
            mock.patch.object(admission.time, "sleep", oversleep),
            self.assertRaises(SbxError) as refused,
        ):
            self.sandboxes().create(self.wait_request("t1", wait=0.3))
        self.assertEqual(refused.exception.code, "wait-timeout")
        self.assertNotIn("sbx-t1", self.backend.domains_by_name)
        self.assertFalse(self.paths.sandbox("t1").exists())
        self.assertEqual(self.queued(), [])

    def test_fifo_order(self) -> None:
        """Waiters start in arrival order as slots free, and list shows their positions."""
        first = self.start("a")
        wait_until(lambda: self.queued() == ["a"])
        self.start("b")
        wait_until(lambda: self.queued() == ["a", "b"])
        listed = self.sandboxes().listing(mine=False)
        self.assertEqual(
            [(entry["name"], entry["state"]) for entry in listed[-2:]],
            [("a", "queued"), ("b", "queued")],
        )
        self.assertEqual([entry["position"] for entry in listed[-2:]], [1, 2])
        self.assertEqual(
            [entry["name"] for entry in self.sandboxes().listing(mine=True)], ["a", "b"]
        )
        self.free("r0")
        first.join(10)
        self.assertEqual(self.results["a"]["name"], "a")
        time.sleep(0.3)
        self.assertNotIn("b", self.results)
        self.assertEqual(self.queued(), ["b"])
        self.free("r1")
        wait_until(lambda: "b" in self.results)
        self.assertEqual(self.results["b"]["name"], "b")
        self.assertEqual(self.queued(), [])
        messages = [call.args[0] for call in self.journal_record.call_args_list]
        self.assertTrue(any(message.startswith("b leaves the queue") for message in messages))

    def test_head_of_line_is_not_overtaken(self) -> None:
        """A small request behind a large one waits, and a create without a wait refuses."""
        self.free("r1")
        self.free("r2")
        with self.sandboxes().locked():
            self.backend.add("big", expires=NOW + 60, memory=8192)
        # 2G and 8G run of 12G: 6G more does not fit, 2G would.
        self.start("large", memory=6144)
        wait_until(lambda: self.queued() == ["large"])
        self.start("small")
        wait_until(lambda: self.queued() == ["large", "small"])
        time.sleep(0.3)
        self.assertEqual(self.results, {})
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request(memory="1G"))
        self.assertEqual(refused.exception.code, "over-limit")
        self.assertEqual(refused.exception.details["waiting"], 2)
        self.free("big")
        wait_until(lambda: set(self.results) == {"large", "small"})
        self.assertEqual(self.results["large"]["name"], "large")
        self.assertEqual(self.results["small"]["name"], "small")

    def test_dead_tickets_are_dropped(self) -> None:
        """Tickets of exited processes or reused pids, staged ones included, never block."""
        self.free("r0")
        exited = subprocess.Popen(["true"])
        exited.wait()
        own = os.getpid()
        self.paths.queue.mkdir(parents=True)
        stale = [
            self.paths.queue / f"0000000001-{exited.pid}-1",
            self.paths.queue / f"0000000002-{own}-1",
            self.paths.queue / f".0000000003-{exited.pid}-1",
        ]
        for path in stale:
            path.write_text("{}")
        self.assertEqual(self.sandboxes().create(self.request())["name"], "t1")
        self.assertEqual(list(self.paths.queue.iterdir()), [])

    def test_expired_and_zombie_tickets_are_dropped(self) -> None:
        """A ticket past its deadline, as a stopped waiter leaves, or of a zombie never blocks."""
        self.free("r0")
        zombie = subprocess.Popen(["true"])
        self.addCleanup(zombie.wait)
        stat = Path(f"/proc/{zombie.pid}/stat")
        wait_until(lambda: stat.read_text().rpartition(")")[2].split()[0] == "Z")
        start = int(stat.read_text().rpartition(")")[2].split()[19])
        self.paths.queue.mkdir(parents=True)
        fields = {"name": "x", "base": "nixos", "memory_mib": 256, "session": None, "queued": NOW}
        expired = fields | {"deadline": waitqueue.boottime() - waitqueue.GRACE - 1}
        own = self.paths.queue / f"0000000001-{os.getpid()}-{waitqueue.process_start(os.getpid())}"
        own.write_text(json.dumps(expired))
        dead = self.paths.queue / f"0000000002-{zombie.pid}-{start}"
        dead.write_text(json.dumps(fields | {"deadline": waitqueue.boottime() + 600}))
        self.assertEqual(self.sandboxes().create(self.request())["name"], "t1")
        self.assertEqual(list(self.paths.queue.iterdir()), [])

    def test_wait_ceiling_and_disk_refuse_before_queueing(self) -> None:
        """A wait past the longest TTL less the boot time, or a passed disk limit, never queues."""
        self.assertEqual(self.request(wait="1439m").wait, 1439 * 60)
        with self.assertRaises(SbxError) as refused:
            self.request(wait="24h")
        self.assertEqual(refused.exception.code, "over-limit")
        self.settings = dataclasses.replace(self.settings, min_free_bytes=1 << 62)
        began = time.monotonic()
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.wait_request("t1"))
        self.assertEqual(refused.exception.code, "disk-full")
        self.assertLess(time.monotonic() - began, 1)
        self.assertEqual(self.queued(), [])

    def test_managed_save_keeps_its_slot(self) -> None:
        """A sandbox saved across host sleep holds its slot until restore."""
        self.free("r2")
        with self.sandboxes().locked():
            self.backend.add("h", expires=NOW + 60, active=False, managed_save=True)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(self.request())
        self.assertEqual(refused.exception.code, "over-limit")
        holders = cast("list[dict[str, object]]", refused.exception.details["holders"])
        self.assertIn("h", [holder["name"] for holder in holders])

    def test_signals_remove_the_ticket(self) -> None:
        """SIGTERM and SIGINT during a wait remove the ticket and restore SIGTERM's handler."""
        previous = signal.getsignal(signal.SIGTERM)
        for signum, raised in ((signal.SIGTERM, SystemExit), (signal.SIGINT, KeyboardInterrupt)):
            with self.subTest(signal=signum):

                def interrupt(signum: int = signum) -> None:
                    wait_until(lambda: self.queued() == ["t1"])
                    os.kill(os.getpid(), signum)

                thread = threading.Thread(target=interrupt)
                thread.start()
                with self.assertRaises(raised):
                    self.sandboxes().create(self.wait_request("t1"))
                thread.join()
                self.assertEqual(self.queued(), [])
                self.assertEqual(list(self.paths.queue.iterdir()), [])
                self.assertIs(signal.getsignal(signal.SIGTERM), previous)

    def test_cancel_ends_the_wait(self) -> None:
        """A cancelled MCP call stops waiting and removes its ticket."""
        sandboxes = self.sandboxes()
        cancelled = threading.Event()
        sandboxes.cancelled = cancelled.is_set
        threading.Timer(0.2, cancelled.set).start()
        with self.assertRaises(SbxError) as refused:
            sandboxes.create(self.wait_request("t1"))
        self.assertEqual(refused.exception.code, "cancelled")
        self.assertEqual(self.queued(), [])

    def test_wait_does_not_count_against_the_ttl(self) -> None:
        """The TTL starts when the sandbox does, not when its create queued."""
        sandboxes = Sandboxes(
            self.settings, self.paths, lambda _slice: self.backend, "claude:one", time.time
        )
        threading.Timer(2.0, self.free, ("r0",)).start()
        result = sandboxes.create(self.wait_request("t1"))
        self.assertGreaterEqual(cast("int", result["ttl_left"]), 3599)


if __name__ == "__main__":
    unittest.main()
