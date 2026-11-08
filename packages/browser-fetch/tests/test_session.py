# Copyright (c) 2026 Bad3r
"""The session's redirect guard policy and the browser's environment."""

import json
import os
import tempfile
import unittest
import unittest.mock
import urllib.request
from pathlib import Path

from browser_fetch import session

from tests import namespaces

TARGET = "https://a.example/start"


class PolicyTest(unittest.TestCase):
    """Top-level document requests, held to WebFetch's redirect policy before they are sent."""

    def policy(self) -> session.Policy:
        """A policy for a fetch of TARGET."""
        return session.Policy(target=TARGET, token="t")  # noqa: S106 - a test token

    def test_target_and_same_host_redirects_go(self) -> None:
        """The fetch's own URL and a same-host redirect, and that redirect's request, go out."""
        policy = self.policy()
        self.assertTrue(policy.check("navigate", "", TARGET, 0))
        self.assertTrue(policy.check("redirect", TARGET, "https://www.a.example/next", 302))
        self.assertTrue(policy.check("navigate", "", "https://www.a.example/next", 0))
        self.assertIsNone(policy.blocked)

    def test_redirect_to_another_host_is_stopped_and_kept(self) -> None:
        """The first refused hop is recorded with its status; nothing goes out after it."""
        policy = self.policy()
        self.assertFalse(policy.check("redirect", TARGET, "https://login.b.example/", 302))
        self.assertEqual(
            policy.blocked,
            {"origin": TARGET, "target": "https://login.b.example/", "status": 302},
        )
        self.assertFalse(policy.check("navigate", "", TARGET, 0))

    def test_hop_that_redirects_back_is_never_sent(self) -> None:
        """An off-host hop is refused before it is requested, whatever follows it."""
        policy = self.policy()
        self.assertFalse(policy.check("redirect", TARGET, "https://track.b.example/?r=back", 301))
        self.assertFalse(policy.check("navigate", "", "https://track.b.example/?r=back", 0))

    def test_script_navigation(self) -> None:
        """A page's own navigation follows the policy from the page it leaves."""
        policy = self.policy()
        self.assertTrue(policy.check("navigate", TARGET, "https://a.example/other", 0))
        self.assertFalse(policy.check("navigate", TARGET, "http://a.example/plain", 0))
        self.assertEqual(policy.blocked and policy.blocked["target"], "http://a.example/plain")

    def test_unrequested_browser_navigation_is_refused(self) -> None:
        """A browser-initiated load of anything but the target is refused."""
        self.assertFalse(self.policy().check("navigate", "", "https://a.example/elsewhere", 0))

    def test_server_needs_the_token(self) -> None:
        """Only the guard addon, holding the token, gets an answer other than refusal."""
        policy = self.policy()
        server = session.policy_server(policy)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        url = f"http://127.0.0.1:{server.server_port}/check"
        body = json.dumps({"kind": "navigate", "from": "", "to": TARGET, "status": 0}).encode()
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def ask(token: str) -> bool:
            request = urllib.request.Request(url, data=body, headers={"X-Token": token})
            with opener.open(request, timeout=5) as reply:
                return bool(json.loads(reply.read())["allow"])

        self.assertFalse(ask("wrong"))
        self.assertTrue(ask("t"))


class EnvironmentTest(unittest.TestCase):
    """What the browser inherits."""

    def test_no_session_display_bus_or_runtime_dir(self) -> None:
        """The browser sees only the private display, never the user's X, Wayland or D-Bus."""
        hostile = {
            "DISPLAY": ":0",
            "XAUTHORITY": "/home/u/.Xauthority",
            "WAYLAND_DISPLAY": "wayland-0",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
            "XDG_RUNTIME_DIR": "/run/user/1000",
            "TZ": "Europe/Prague",
        }
        with unittest.mock.patch.dict(os.environ, hostile, clear=True):
            env = session.browser_env(Path("/state/home"), ":7")
        self.assertEqual(env["DISPLAY"], ":7")
        for key in ("XAUTHORITY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR"):
            self.assertNotIn(key, env)
        self.assertEqual(env["TZ"], "Europe/Prague")
        self.assertEqual(env["HOME"], "/state/home")


CONFINED = """\
import errno, json, socket, subprocess, time
from pathlib import Path
from browser_fetch import browser, session, tools
work = Path(sys.argv[1])
(work / browser.NETWORK_READY).write_text("")
session.private_tmp([work])
session.await_network(work, time.monotonic() + 20)
session.confine_network()
session.drop_capabilities()

def connect(address):
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    with socket.socket(family, socket.SOCK_STREAM) as probe:
        probe.settimeout(2)
        try:
            probe.connect((address, 80))
        except OSError as error:
            return errno.errorcode.get(error.errno, str(error.errno))
    return "connected"

out = {a: connect(a) for a in sys.argv[2:]}
removed = subprocess.run([tools.IP, "rule", "del", "pref", "100"], capture_output=True)
out["rule del"] = removed.returncode
print(json.dumps(out))
"""


class ConfinementTest(unittest.TestCase):
    """The session's namespace refuses blocked ranges by rule, and the browser cannot undo it."""

    @classmethod
    def setUpClass(cls) -> None:
        """Skip, saying why, where the host cannot make the session's namespace."""
        namespaces.require_namespaces()

    def test_blocked_ranges_are_prohibited_and_public_ones_are_not(self) -> None:
        """Private addresses fail with EACCES from a rule; a public one only lacks a route here."""
        private = ["10.0.0.1", "100.96.0.9", "169.254.169.254", "172.16.0.1", "192.168.1.1"]
        with tempfile.TemporaryDirectory(prefix="browser-fetch-test-") as work:
            ran = namespaces.run_in_namespace(
                CONFINED.replace("sys.argv[2:]", repr([*private, "93.184.215.14"])), Path(work)
            )
        self.assertEqual(ran.returncode, 0, ran.stderr)
        out = json.loads(ran.stdout)
        for address in private:
            with self.subTest(address=address):
                self.assertEqual(out[address], "EACCES")
        self.assertEqual(out["93.184.215.14"], "ENETUNREACH")
        self.assertNotEqual(out["rule del"], 0)
