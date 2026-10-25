# Copyright (c) 2026 Bad3r
"""Requests checked against the ceilings, and the queue for capacity."""

import contextlib
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING, cast

from sbx import journal, waitqueue
from sbx.config import parse_duration, parse_memory
from sbx.errors import SbxError
from sbx.model import DOMAIN_PREFIX, FLAVOURS, GUI_BASES, NETS, Request
from sbx.storage import Storage

if TYPE_CHECKING:
    from collections.abc import Generator

    from sbx.config import Egress
    from sbx.model import Backend, Sandbox


SYS_NET = Path("/sys/class/net")
IFF_UP = 0x1
WAIT_POLL = 2.0
# The `--wait` an over-limit refusal suggests.
RETRY_WAIT = "30m"


class Admission(Storage):
    """Validation of create requests and admission under the ceilings."""

    def _check_egress(self) -> Egress:
        """Return the egress bridge, refusing when it is not declared, absent, or down."""
        egress = self.settings.egress
        if isinstance(egress, str):
            raise SbxError(egress, code="egress-unavailable")
        device = SYS_NET / egress.bridge
        absent = f"bridge {egress.bridge} does not exist; its libvirt network is not running"
        if not (device / "bridge").is_dir():
            raise SbxError(absent, code="egress-unavailable")
        try:
            flags = int((device / "flags").read_text(), 16)
        except FileNotFoundError as error:
            raise SbxError(absent, code="egress-unavailable") from error
        if not flags & IFF_UP:
            msg = f"bridge {egress.bridge} is down"
            raise SbxError(msg, code="egress-unavailable")
        return egress

    def request(  # noqa: PLR0913
        self,
        base: str,
        *,
        name: str | None,
        net: str,
        memory: str | None,
        cpus: int | None,
        ttl: str | None,
        gui: bool = False,
        wait: str | None = None,
    ) -> Request:
        """Turn create flags into a request within the ceilings; `gui` picks `<base>-gui`."""
        settings = self.settings
        if gui and base not in GUI_BASES:
            if f"{base}-gui" not in GUI_BASES:
                msg = f"base '{base}' has no GUI variant; GUI bases: {', '.join(sorted(GUI_BASES))}"
                raise SbxError(msg, code="unknown-base")
            base = f"{base}-gui"
        windows_settings = self.windows_base(base)
        if windows_settings is not None:
            default_memory = windows_settings.memory_mib
        elif base in GUI_BASES:
            default_memory = settings.default_gui_memory_mib
        else:
            default_memory = settings.default_memory_mib
        request = Request(
            base,
            name,
            net,
            default_memory if memory is None else parse_memory(memory),
            settings.default_cpus if cpus is None else cpus,
            settings.default_ttl if ttl is None else parse_duration(ttl),
            None if wait is None else parse_duration(wait),
        )
        self._validate(request)
        return request

    def _validate(self, request: Request) -> None:
        settings = self.settings
        if request.base not in self._bases():
            msg = f"unknown base '{request.base}'; bases: {', '.join(self._bases())}"
            raise SbxError(msg, code="unknown-base")
        # Clones share the golden copy's SIDs, which stay harmless only off the network.
        if self.windows_base(request.base) is not None and request.net != "none":
            msg = "Windows bases run without a network"
            raise SbxError(msg, code="invalid-argument")
        if request.name is not None:
            self._check_name(request.name)
        if request.net not in NETS:
            msg = f"network '{request.net}' is not available; networks: {', '.join(NETS)}"
            raise SbxError(msg, code="invalid-argument")
        if not 256 <= request.memory_mib <= settings.sandbox_memory_mib:  # noqa: PLR2004
            msg = f"memory must be 256M to {settings.sandbox_memory_mib}M"
            raise SbxError(msg, code="over-limit")
        if not 1 <= request.cpus <= settings.sandbox_cpus:
            msg = f"cpus must be 1 to {settings.sandbox_cpus}"
            raise SbxError(msg, code="over-limit")
        if not 60 <= request.ttl <= settings.max_ttl:  # noqa: PLR2004
            msg = f"ttl must be 1m to {settings.max_ttl // 3600}h"
            raise SbxError(msg, code="over-limit")
        # The MCP tool timeout is the longest TTL, which must also cover the boot.
        longest_wait = settings.max_ttl - settings.boot_timeout
        if request.wait is not None and request.wait > longest_wait:
            msg = (
                f"wait must be at most {longest_wait // 60}m, the longest TTL less the boot timeout"
            )
            raise SbxError(msg, code="over-limit")

    def _bases(self) -> list[str]:
        windows_bases = [] if self.settings.windows is None else list(self.settings.windows.bases)
        return [*FLAVOURS, *self.settings.cloud_images, *windows_bases]

    def _holders(self) -> list[Sandbox]:
        """Return the sandboxes that take a slot: running ones and those a managed save holds."""
        return [
            sandbox
            for sandbox in self.owned()
            if sandbox.domain.active or sandbox.domain.managed_save
        ]

    def _capacity_problem(self, request: Request) -> str | None:
        """Say why the running or memory ceiling leaves no room for `request`, if one does."""
        running = [sandbox.domain for sandbox in self._holders()]
        if len(running) >= self.settings.running:
            return f"{len(running)} sandboxes run, the ceiling is {self.settings.running}"
        declared = sum(domain.memory_mib for domain in running)
        if declared + request.memory_mib > self.settings.memory_mib:
            return (
                f"running sandboxes declare {declared}M; {request.memory_mib}M more exceeds "
                f"the {self.settings.memory_mib}M ceiling"
            )
        return None

    def _capacity_error(self, problem: str, ahead: int, *, code: str) -> SbxError:
        """Name who holds the capacity and, for over-limit, how to get it."""
        now = int(self._clock())
        running = self._holders()
        held = ", ".join(
            f"{sandbox.name} ({sandbox.meta.session or 'no session'}, "
            f"{max(0, sandbox.meta.expires - now) // 60}m left)"
            for sandbox in running
        )
        msg = f"{problem}; held by {held or 'no sbx sandbox'}"
        if ahead:
            msg += f"; {ahead} queued ahead"
        details: dict[str, object] = {
            "holders": [
                {
                    "name": sandbox.name,
                    "session": sandbox.meta.session,
                    "memory_mib": sandbox.domain.memory_mib,
                    "ttl_left": max(0, sandbox.meta.expires - now),
                }
                for sandbox in running
            ],
            "waiting": ahead,
        }
        if code == "over-limit":
            msg += (
                f". Rerun the same command with --wait {RETRY_WAIT} (MCP: wait) in the "
                "background and check back, or destroy your own idle sandboxes with "
                "`sbx destroy --mine`"
            )
            details["retry"] = {"wait": RETRY_WAIT}
        return SbxError(msg, code=code, details=details)

    def _ahead(self, ticket: waitqueue.Ticket | None) -> list[waitqueue.Ticket]:
        """Return the live tickets older than `ticket`, or every one for a new request."""
        queue = waitqueue.live(self.paths.queue)
        return [entry for entry in queue if ticket is None or entry.seq < ticket.seq]

    def _enqueue(
        self, request: Request, name: str, problem: str, position: int, deadline: float
    ) -> waitqueue.Ticket:
        # Waiting never clears a disk limit already passed.
        self.check_disk()
        ticket = waitqueue.enqueue(
            self.paths.queue,
            name=name,
            base=request.base,
            memory_mib=request.memory_mib,
            session=self.session,
            queued=int(self._clock()),
            deadline=deadline,
        )
        journal.record(
            f"{name} queues for capacity at position {position}: {problem}",
            verb="create",
            sandbox=name,
            session=self.session,
        )
        print(f"sbx: {name} queues at position {position}: {problem}", file=sys.stderr)
        return ticket

    def _dequeue(self, ticket: waitqueue.Ticket | None, started: float | None) -> None:
        """Drop a ticket; with `started`, its create proceeds, which the journal records."""
        if ticket is None or not ticket.path.exists():
            return
        ticket.path.unlink(missing_ok=True)
        if started is not None:
            journal.record(
                f"{ticket.name} leaves the queue after {waitqueue.boottime() - started:.0f} s",
                verb="create",
                sandbox=ticket.name,
                session=self.session,
            )

    def _claim(
        self, request: Request, name: str, ticket: waitqueue.Ticket | None
    ) -> tuple[str | None, int]:
        """Refuse a taken name; return what keeps the request out and the count queued ahead."""
        # Each attempt reconnects, since a waiter may outlast a daemon restart.
        backend = self.backend(require_slice=True)
        if self.paths.sandbox(name).exists() or any(
            info.name == DOMAIN_PREFIX + name for info in backend.domains()
        ):
            msg = f"a sandbox named '{name}' exists"
            raise SbxError(msg, code="exists")
        ahead = len(self._ahead(ticket))
        problem = self._capacity_problem(request)
        if problem is None and ahead:
            problem = "earlier creates queue for capacity"
        return problem, ahead

    @contextlib.contextmanager
    def _admitted(self, request: Request, name: str) -> Generator[Backend]:
        """Hold the lock once `name` is free and the request fits the running and memory ceilings.

        With `request.wait`, a request that does not fit queues behind earlier
        waiters and proceeds only at the head of the queue, so a large request
        is never overtaken. A request without a wait never jumps the queue.
        """
        started = waitqueue.boottime()
        deadline = started + (request.wait or 0)
        ticket: waitqueue.Ticket | None = None
        try:
            while True:
                if self.cancelled():
                    msg = f"the create of '{name}' was cancelled while it waited"
                    raise SbxError(msg, code="cancelled")
                # Waiters behind the head skip the lock and the daemon.
                if ticket is None or not self._ahead(ticket):
                    with self.locked():
                        problem, ahead = self._claim(request, name, ticket)
                        # A waiter woken past its deadline, as after host sleep, never starts.
                        if problem is None and (ticket is None or waitqueue.boottime() < deadline):
                            self._dequeue(ticket, started)
                            yield self.backend()
                            return
                        if request.wait is None:
                            raise self._capacity_error(
                                cast("str", problem), ahead, code="over-limit"
                            )
                        ticket = ticket or self._enqueue(
                            request, name, cast("str", problem), ahead + 1, deadline
                        )
                remaining = deadline - waitqueue.boottime()
                if remaining <= 0:
                    raise self._wait_timeout(request, name, ticket)
                time.sleep(min(WAIT_POLL, remaining))
        finally:
            self._dequeue(ticket, None)

    def _wait_timeout(
        self, request: Request, name: str, ticket: waitqueue.Ticket | None
    ) -> SbxError:
        problem = self._capacity_problem(request)
        message = f"'{name}' waited {request.wait:g} s for capacity"
        if problem is not None:
            message += f": {problem}"
        return self._capacity_error(message, len(self._ahead(ticket)), code="wait-timeout")
