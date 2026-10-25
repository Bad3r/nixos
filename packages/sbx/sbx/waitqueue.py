# Copyright (c) 2026 Bad3r
"""First-come-first-served tickets of creates that wait for sandbox capacity.

A ticket is a file named `<seq>-<pid>-<start>`, where `start` is the
process's start time in clock ticks since boot, so a ticket whose process is
gone, or whose pid now belongs to another process, is dropped on sight.
"""

import json
import os
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

TICKET = re.compile(r"(\d+)-(\d+)-(\d+)")


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


def process_start(pid: int) -> int | None:
    """Return a process's start time in clock ticks since boot, or None once it is gone."""
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except FileNotFoundError, ProcessLookupError:
        return None
    # Field 22; the command name before it may hold spaces and parentheses.
    return int(stat.rpartition(")")[2].split()[19])


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
        tickets.append(
            Ticket(
                entry,
                seq,
                fields["name"],
                fields["base"],
                fields["memory_mib"],
                fields["session"],
                fields["queued"],
            )
        )
    return sorted(tickets, key=lambda ticket: ticket.seq)


def enqueue(  # noqa: PLR0913
    directory: Path, *, name: str, base: str, memory_mib: int, session: str | None, queued: int
) -> Ticket:
    """Add a ticket behind every live one; the caller holds the state lock."""
    directory.mkdir(mode=0o700, exist_ok=True)
    seq = max((ticket.seq for ticket in live(directory)), default=0) + 1
    pid = os.getpid()
    path = directory / f"{seq:010d}-{pid}-{process_start(pid)}"
    staged = path.with_name(f".{path.name}")
    fields = {
        "name": name,
        "base": base,
        "memory_mib": memory_mib,
        "session": session,
        "queued": queued,
    }
    staged.write_text(json.dumps(fields))
    staged.rename(path)
    return Ticket(path, seq, name, base, memory_mib, session, queued)
