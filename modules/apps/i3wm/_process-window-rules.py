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
        self.applied: set[tuple[int, str]] = set()
        self.marker = "__process_window_rule_" + uuid4().hex

    def execute(self, con: i3ipc.Con, rule: dict) -> bool:
        """Probe native criteria because i3 reports success even for zero matches."""
        selector = f'[con_id={con.id} con_mark="^{self.marker}$"]'
        try:
            replies = self.ipc.command(
                f"[con_id={con.id} {rule['criteria']}] mark --add {self.marker}"
            )
            if not all(reply.success for reply in replies):
                for reply in replies:
                    if not reply.success:
                        LOG.error("Rule %s has invalid criteria: %s", rule["name"], reply.error)
                return False
            current = self.ipc.get_tree().find_by_id(con.id)
            if current is None or self.marker not in current.marks:
                return False
            replies = self.ipc.command(f"{selector} {rule['command']}")
            for reply in replies:
                if not reply.success:
                    LOG.error("Rule %s failed: %s", rule["name"], reply.error)
            return all(reply.success for reply in replies)
        finally:
            self.ipc.command(f"{selector} unmark {self.marker}")

    def apply(self, con: i3ipc.Con) -> None:
        """Apply each matching rule once while the container exists."""
        if not con.window:
            return
        try:
            window = self.x11.create_resource_object("window", con.window)
            prop = window.get_full_property(self.pid_atom, Xatom.CARDINAL)
            if prop is None or len(prop.value) != 1:
                return
            argv = Path(f"/proc/{int(prop.value[0])}/cmdline").read_bytes().split(b"\0")
        except error.BadWindow, FileNotFoundError, ProcessLookupError:
            # A close can overtake a queued window event or the initial scan.
            return
        except PermissionError:
            LOG.warning("Cannot read process arguments for window %#x", con.window)
            return

        for rule in self.rules:
            key = (con.id, rule["name"])
            if key in self.applied or not all(
                arg.encode() in argv[1:] for arg in rule["processArgs"]
            ):
                continue
            if self.execute(con, rule):
                self.applied.add(key)

    def on_window(self, _ipc: i3ipc.Connection, event: i3ipc.WindowEvent) -> None:
        """Retry on title changes and forget closed containers."""
        if event.change == "close":
            self.applied = {key for key in self.applied if key[0] != event.container.id}
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
