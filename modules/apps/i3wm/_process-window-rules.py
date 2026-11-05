# Copyright (c) 2026 Bad3r
"""Apply i3 rules that also require exact arguments in the window owner's argv.

Usage: python3 _process-window-rules.py rules.json
"""

import json
import logging
import sys
from pathlib import Path
from uuid import uuid4

import i3ipc
from Xlib import Xatom, display, error

LOG = logging.getLogger("i3-process-window-rules")


class WindowRules:
    """Filter by process argv and delegate window criteria to i3."""

    def __init__(self, ipc: i3ipc.Connection, rules: list[dict]) -> None:
        self.ipc = ipc
        self.rules = rules
        self.x11 = display.Display()
        self.pid_atom = self.x11.intern_atom("_NET_WM_PID")
        # Rules whose process filter matched a container and have not applied yet.
        self.pending: dict[int, list[dict]] = {}
        self.marker = "__process_window_rule_" + uuid4().hex

    def execute(self, con: i3ipc.Con, rule: dict) -> bool:
        """Probe native criteria because i3 reports success even for zero matches.

        Return whether the rule is settled for this container: applied, or rejected
        by i3 so that later events do not repeat the same error.
        """
        selector = f'[con_id={con.id} con_mark="^{self.marker}$"]'
        try:
            replies = self.ipc.command(
                f"[con_id={con.id} {rule['criteria']}] mark --add {self.marker}"
            )
            rejected = [reply for reply in replies if reply.ipc_data.get("parse_error")]
            for reply in rejected:
                LOG.error("Rule %s has invalid criteria: %s", rule["name"], reply.error)
            if rejected:
                return True
            # i3 refuses to mark when the criteria match no window.
            if (
                not all(reply.success for reply in replies)
                or self.marker not in self.ipc.get_marks()
            ):
                return False
            replies = self.ipc.command(f"{selector} {rule['command']}")
            for reply in replies:
                if not reply.success:
                    LOG.error("Rule %s failed: %s", rule["name"], reply.error)
            return True
        finally:
            self.ipc.command(f"{selector} unmark {self.marker}")

    def candidates(self, con: i3ipc.Con) -> list[dict] | None:
        """Read the owner's argv once per container and keep the rules it satisfies."""
        try:
            window = self.x11.create_resource_object("window", con.window)
            prop = window.get_full_property(self.pid_atom, Xatom.CARDINAL)
            if prop is None or len(prop.value) != 1:
                return None
            argv = Path(f"/proc/{int(prop.value[0])}/cmdline").read_bytes().split(b"\0")
        except error.BadWindow, FileNotFoundError, ProcessLookupError:
            # A close can overtake a queued window event or the initial scan.
            return None
        except PermissionError:
            LOG.warning("Cannot read process arguments for window %#x", con.window)
            return None
        return [
            rule
            for rule in self.rules
            if all(arg.encode() in argv[1:] for arg in rule["processArgs"])
        ]

    def apply(self, con: i3ipc.Con) -> None:
        """Apply each matching rule once while the container exists."""
        if not con.window:
            return
        if con.id not in self.pending:
            rules = self.candidates(con)
            if rules is None:
                return
            self.pending[con.id] = rules
        self.pending[con.id] = [
            rule for rule in self.pending[con.id] if not self.execute(con, rule)
        ]

    def on_window(self, _ipc: i3ipc.Connection, event: i3ipc.WindowEvent) -> None:
        """Retry on title changes and forget closed containers."""
        if event.change == "close":
            self.pending.pop(event.container.id, None)
        else:
            self.apply(event.container)

    def on_tick(self, _ipc: i3ipc.Connection, event: i3ipc.TickEvent) -> None:
        """Scan after subscribing so windows opened during startup are covered."""
        if event.first:
            for con in self.ipc.get_tree().descendants():
                self.apply(con)
            LOG.info("Window rules ready")


def main() -> None:
    """Watch i3 until it closes the IPC connection."""
    logging.basicConfig(level=logging.INFO, format="%(name)s: %(levelname)s: %(message)s")
    rules = json.loads(Path(sys.argv[1]).read_text())
    ipc = i3ipc.Connection()
    watcher = WindowRules(ipc, rules)
    ipc.on(i3ipc.Event.WINDOW_NEW, watcher.on_window)
    ipc.on(i3ipc.Event.WINDOW_TITLE, watcher.on_window)
    ipc.on(i3ipc.Event.WINDOW_CLOSE, watcher.on_window)
    ipc.on(i3ipc.Event.TICK, watcher.on_tick)
    ipc.main()


if __name__ == "__main__":
    main()
