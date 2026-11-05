# Copyright (c) 2026 Bad3r
"""Exercise process-aware rules with real i3 and X clients on a private Xvfb."""

import json
import os
import select
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import TYPE_CHECKING

import i3ipc
from Xlib import X, Xatom, display

if TYPE_CHECKING:
    from collections.abc import Callable

SUBJECT = Path(__file__).resolve().parents[2] / "modules/apps/i3wm/_process-window-rules.py"


def client(spec: dict) -> None:
    """Own a window in a separate process with its actual PID property."""
    x11 = display.Display()
    window = x11.screen().root.create_window(
        0, 0, 300, 200, 0, X.CopyFromParent, X.InputOutput, X.CopyFromParent
    )
    window.set_wm_class(spec["instance"], spec["class"])
    window.change_property(x11.intern_atom("_NET_WM_PID"), Xatom.CARDINAL, 32, [os.getpid()])

    def title(value: str) -> None:
        window.set_wm_name(value)
        window.change_property(
            x11.intern_atom("_NET_WM_NAME"), x11.intern_atom("UTF8_STRING"), 8, value.encode()
        )
        x11.sync()

    title(spec["title"])
    window.map()
    x11.sync()
    print(window.id, flush=True)
    for line in sys.stdin:
        title(json.loads(line))
    window.destroy()
    x11.sync()
    x11.close()


class RuntimeRules(unittest.TestCase):
    """Check inclusion, exclusion, startup, and delayed-title behavior."""

    def setUp(self) -> None:
        """Allocate an X server and i3 that cannot reach the live session."""
        self.temp = tempfile.TemporaryDirectory(prefix="i3-window-rules-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ)
        for name in ("DISPLAY", "I3SOCK", "SWAYSOCK", "XAUTHORITY"):
            self.env.pop(name, None)
        self.env.update(
            HOME=str(self.root),
            XDG_RUNTIME_DIR=str(self.root),
            XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_CACHE_HOME=str(self.root / "cache"),
            XDG_DATA_HOME=str(self.root / "data"),
        )
        self.log = (self.root / "processes.log").open("w+")
        self.addCleanup(self.log.close)
        read_fd, write_fd = os.pipe()
        try:
            self.spawn(
                [
                    "Xvfb",
                    "-displayfd",
                    str(write_fd),
                    "-screen",
                    "0",
                    "1024x768x24",
                    "-nolisten",
                    "tcp",
                ],
                pass_fds=(write_fd,),
            )
        finally:
            os.close(write_fd)
        with os.fdopen(read_fd) as display_file:
            if not select.select([display_file], [], [], 5)[0]:
                self.fail("Xvfb did not allocate a display")
            self.env["DISPLAY"] = ":" + display_file.readline().strip()
        self.socket = self.root / "i3.sock"
        config = self.root / "i3.conf"
        config.write_text(f"font pango:monospace 8\nipc-socket {self.socket}\n")
        self.spawn(["i3", "-c", str(config)])
        self.wait_for(self.socket.exists, "i3 IPC socket")
        self.ipc = i3ipc.Connection(socket_path=str(self.socket))
        # i3ipc exposes no public close method for command-only connections.
        self.addCleanup(self.ipc._cmd_socket.close)  # noqa: SLF001
        self.rules = [
            {
                "name": "rustdesk-connection-manager",
                "criteria": 'class="(?i)^rustdesk$" instance="(?i)^rustdesk$"',
                "command": "floating enable",
                "processArgs": ["--cm"],
            }
        ]

    def tearDown(self) -> None:
        """Check that native matching leaves no private marks behind."""
        self.wait_for(
            lambda: (
                not any(mark.startswith("__process_window_rule_") for mark in self.ipc.get_marks())
            ),
            "temporary rule marks to be removed",
        )

    def spawn(self, command: list[str], **kwargs: object) -> subprocess.Popen:
        """Start a fixture process and register bounded cleanup."""
        proc = subprocess.Popen(command, env=self.env, stderr=self.log, stdout=self.log, **kwargs)
        self.addCleanup(self.stop, proc)
        return proc

    @staticmethod
    def stop(proc: subprocess.Popen) -> None:
        """Reap each fixture process before removing its private directory."""
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        for stream in (proc.stdin, proc.stdout):
            if stream is not None:
                stream.close()

    def wait_for(self, predicate: Callable[[], object], description: str) -> None:
        """Wait for an observed condition rather than a startup delay."""
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        self.log.flush()
        self.fail(
            f"Timed out waiting for {description}:\n{(self.root / 'processes.log').read_text()}"
        )

    def window(
        self,
        title: str = "RustDesk",
        args: tuple[str, ...] = (),
        wm_class: str = "Rustdesk",
        instance: str = "rustdesk",
    ) -> tuple[int, subprocess.Popen]:
        """Map a client whose command-line identity cannot be inherited from the test."""
        spec = {"title": title, "class": wm_class, "instance": instance}
        proc = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--client", json.dumps(spec), *args],
            env=self.env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.log,
            text=True,
        )
        self.addCleanup(self.stop, proc)
        if not select.select([proc.stdout], [], [], 5)[0]:
            self.fail("Client did not map its window")
        window_id = int(proc.stdout.readline())
        self.wait_for(lambda: self.ipc.get_tree().find_by_window(window_id), "managed client")
        return window_id, proc

    def start_rules(self) -> subprocess.Popen:
        """Start the actual subject and wait for its subscription and scan."""
        config = self.root / "rules.json"
        config.write_text(json.dumps(self.rules))
        self.env["I3SOCK"] = str(self.socket)
        log_offset = (self.root / "processes.log").stat().st_size
        proc = self.spawn([sys.executable, str(SUBJECT), str(config)])
        self.wait_for(
            lambda: "Window rules ready" in (self.root / "processes.log").read_text()[log_offset:],
            "rule service readiness",
        )
        return proc

    def floating(self, window_id: int) -> bool:
        """Inspect i3's actual container state."""
        con = self.ipc.get_tree().find_by_window(window_id)
        return con is not None and con.floating in {"auto_on", "user_on"}

    def assert_tiled(self, *window_ids: int) -> None:
        """Allow queued events to run before checking all negative cases."""
        time.sleep(0.25)
        for window_id in window_ids:
            if self.ipc.get_tree().find_by_window(window_id) is None:
                self.fail(f"Expected tiled window {window_id:#x} is missing")
            if self.floating(window_id):
                self.fail(f"Window {window_id:#x} unexpectedly floated")

    def test_existing_and_new_connection_managers(self) -> None:
        """Connection-manager identity survives device and initial-title changes."""
        existing, _ = self.window("first-device - RustDesk", ("--cm",))
        self.assert_tiled(existing)
        self.ipc.command(f"[id={existing}] mark --add user-owned")
        self.start_rules()
        self.wait_for(lambda: self.floating(existing), "existing connection-manager floating")
        self.wait_for(
            lambda: self.ipc.get_marks() == ["user-owned"], "existing user mark preservation"
        )
        for title in ("second-device - RustDesk", "third device - RustDesk", "RustDesk"):
            new, _ = self.window(title, ("--cm",))
            self.wait_for(
                lambda window_id=new: self.floating(window_id), "new connection-manager floating"
            )

    def test_main_outgoing_and_argument_prefix_stay_tiled(self) -> None:
        """Identical titles cannot make other RustDesk processes match."""
        self.start_rules()
        main, _ = self.window()
        same_title, _ = self.window("first-device - RustDesk")
        outgoing, _ = self.window("first-device - RustDesk", ("--connect",))
        prefix, _ = self.window("first-device - RustDesk", ("--cm-suffix",))
        self.assert_tiled(main, same_title, outgoing, prefix)

    def test_class_and_instance_must_both_match(self) -> None:
        """Native PCRE criteria retain case folding and AND semantics."""
        self.start_rules()
        wrong_class, _ = self.window(args=("--cm",), wm_class="Other")
        wrong_instance, _ = self.window(args=("--cm",), instance="Other")
        self.assert_tiled(wrong_class, wrong_instance)
        accepted, _ = self.window(args=("--cm",), wm_class="RUSTDESK", instance="RUSTDESK")
        self.wait_for(lambda: self.floating(accepted), "case-insensitive criteria")

    def test_late_title_and_once_only_application(self) -> None:
        """A later match applies once without undoing a manual tiling change."""
        self.rules[0]["criteria"] += ' title="^ready$"'
        self.start_rules()
        window_id, proc = self.window("starting", ("--cm",))
        self.assert_tiled(window_id)
        proc.stdin.write(json.dumps("ready") + "\n")
        proc.stdin.flush()
        self.wait_for(lambda: self.floating(window_id), "late title match")
        reply = self.ipc.command(f"[id={window_id}] floating disable")
        if not all(item.success for item in reply):
            self.fail("Could not tile the fixture window manually")
        proc.stdin.write(json.dumps("different") + "\n" + json.dumps("ready") + "\n")
        proc.stdin.flush()
        self.assert_tiled(window_id)

    def test_closed_windows_do_not_stop_the_service(self) -> None:
        """Rapid closes leave the watcher able to process a subsequent client."""
        subject = self.start_rules()
        for _ in range(6):
            _, proc = self.window(args=("--cm",))
            proc.stdin.close()
            proc.wait(timeout=3)
        final, _ = self.window(args=("--cm",))
        self.wait_for(lambda: self.floating(final), "rules after rapid window closes")
        if subject.poll() is not None:
            self.fail("Rule watcher exited after a window closed")

    def test_watcher_restart_rescans_existing_window(self) -> None:
        """A relaunched watcher recovers its policy from current windows."""
        subject = self.start_rules()
        window_id, _ = self.window(args=("--cm",))
        self.wait_for(lambda: self.floating(window_id), "initial floating rule")
        self.stop(subject)
        self.ipc.command(f"[id={window_id}] floating disable")
        self.assert_tiled(window_id)
        self.start_rules()
        self.wait_for(lambda: self.floating(window_id), "startup scan after watcher restart")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--client":
        client(json.loads(sys.argv[2]))
    else:
        if len(sys.argv) > 1:
            SUBJECT = Path(sys.argv.pop(1)).resolve()
        unittest.main(verbosity=2)
