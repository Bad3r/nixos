# Copyright (c) 2026 Bad3r
"""First-come-first-served tickets of creates that wait for sandbox capacity.

A ticket is a file named `<seq>-<pid>-<start>`, where `start` is the
process's start time in clock ticks since boot, so a ticket whose process is
gone or a zombie, or whose pid now belongs to another process, is dropped on
sight, as is one past its deadline, which a stopped waiter never removes.
"""

import json
import os
import re
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

TICKET = re.compile(r"(\d+)-(\d+)-(\d+)")
# Past its deadline a live waiter removes its own ticket within a poll.
GRACE = 30


@dataclass(frozen=True)
class Ticket:
    """One waiting create."""

    path: Path
    seq: int
    name: str
    base: str
    memory_mib: int
    session: str | None
    queued: int
    # CLOCK_BOOTTIME seconds, which wall-clock steps after resume leave alone.
    deadline: float

    def as_json(self, position: int) -> dict[str, object]:
        """Return the JSON form `sbx list` prints."""
        return {
            "name": self.name,
            "state": "queued",
            "position": position,
            "base": self.base,
            "memory_mib": self.memory_mib,
            "session": self.session,
            "queued": datetime.fromtimestamp(self.queued, UTC).isoformat(timespec="seconds"),
        }


def boottime() -> float:
    """Return seconds since boot, host sleep included."""
    return time.clock_gettime(time.CLOCK_BOOTTIME)


def process_start(pid: int) -> int | None:
    """Return a process's start time in clock ticks since boot; None once it is gone or a zombie."""
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except FileNotFoundError, ProcessLookupError:
        return None
    # Fields 3 and 22; the command name before them may hold spaces and parentheses.
    fields = stat.rpartition(")")[2].split()
    return None if fields[0] == "Z" else int(fields[19])


def live(directory: Path) -> list[Ticket]:
    """Return the live tickets oldest first, removing those of processes that are gone."""
    if not directory.is_dir():
        return []
    tickets: list[Ticket] = []
    for entry in directory.iterdir():
        match = TICKET.fullmatch(entry.name.removeprefix("."))
        if match is None:
            continue
        seq, pid, start = map(int, match.groups())
        if process_start(pid) != start:
            entry.unlink(missing_ok=True)
            continue
        # A dot marks a ticket still being written.
        if entry.name.startswith("."):
            continue
        try:
            fields = json.loads(entry.read_text())
        except FileNotFoundError:
            continue
        if fields["deadline"] + GRACE < boottime():
            entry.unlink(missing_ok=True)
            continue
        tickets.append(
            Ticket(
                entry,
                seq,
                fields["name"],
                fields["base"],
                fields["memory_mib"],
                fields["session"],
                fields["queued"],
                fields["deadline"],
            )
        )
    return sorted(tickets, key=lambda ticket: ticket.seq)


def reserve(  # noqa: PLR0913
    directory: Path,
    *,
    name: str,
    base: str,
    memory_mib: int,
    session: str | None,
    queued: int,
    deadline: float,
) -> Ticket:
    """Return a ticket behind every live one, not yet in the queue; the caller holds the state lock.

    The caller takes the ticket before `publish` creates its file, so an
    exception or signal at any point leaves it something to remove.
    """
    directory.mkdir(mode=0o700, exist_ok=True)
    seq = max((ticket.seq for ticket in live(directory)), default=0) + 1
    pid = os.getpid()
    path = directory / f"{seq:010d}-{pid}-{process_start(pid)}"
    return Ticket(path, seq, name, base, memory_mib, session, queued, deadline)


def publish(ticket: Ticket) -> None:
    """Put a reserved ticket in the queue; on failure only its own path can remain."""
    staged = ticket.path.with_name(f".{ticket.path.name}")
    fields = {
        "name": ticket.name,
        "base": ticket.base,
        "memory_mib": ticket.memory_mib,
        "session": ticket.session,
        "queued": ticket.queued,
        "deadline": ticket.deadline,
    }
    try:
        staged.write_text(json.dumps(fields))
        staged.rename(ticket.path)
    except BaseException:
        staged.unlink(missing_ok=True)
        raise
