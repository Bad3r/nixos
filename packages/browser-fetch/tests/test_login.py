# Copyright (c) 2026 Bad3r
"""browser-fetch login: the display the namespace gets, its arguments, the lock, a real window.

The Xauthority expectations come from xauth's own reading of the files,
and the real run's from an X server that demands the cookie.
"""

from __future__ import annotations

import contextlib
import ctypes
import fcntl
import io
import json
import os
import re
import secrets
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock
from pathlib import Path
from typing import Any, ClassVar

from browser_fetch import browser, cli, display, tools
from browser_fetch import cookies as jar

from tests.namespaces import (
    ROOT,
    require_namespaces,
    run_in_namespace,
    tools_with,
    write_fake_pasta,
)

XAUTH = os.environ.get("BROWSER_FETCH_TEST_XAUTH", "")
XWININFO = os.environ.get("BROWSER_FETCH_TEST_XWININFO", "")
LIBX11 = os.environ.get("BROWSER_FETCH_TEST_LIBX11", "")
VERSION = "158.0.1-beta.41"
MIT = "MIT-MAGIC-COOKIE-1"


def xauth(file: Path, *args: str, stdin: str | None = None) -> str:
    """Run xauth on file and return its output."""
    return subprocess.run(
        [XAUTH, "-q", "-f", str(file), *args],
        input=stdin,
        capture_output=True,
        text=True,
        check=True,
        env={"PATH": "/var/empty", "HOME": str(file.parent)},
    ).stdout


def listening_socket(path: Path) -> socket.socket:
    """A unix socket listening at path."""
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(path))
    server.listen(4)
    return server


@unittest.skipUnless(XAUTH, "BROWSER_FETCH_TEST_XAUTH names no xauth")
class AuthorityTest(unittest.TestCase):
    """The Xauthority file a login's browser gets holds only its display's records."""

    def setUp(self) -> None:
        """A directory for the files."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-xauth-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.host = socket.gethostname()

    def test_only_records_xlib_would_use_for_the_display(self) -> None:
        """This host's records for the display and wildcard ones stay; every other one goes."""
        source = self.tmp / "source"
        kept = {f"{self.host}/unix:0": "00" * 16}
        dropped = {
            f"{self.host}/unix:1": "11" * 16,
            "other.example/unix:0": "22" * 16,
            "10.9.8.7:0": "33" * 16,
        }
        for name, cookie in {**kept, **dropped}.items():
            xauth(source, "add", name, MIT, cookie)
        mit = MIT.encode().hex()
        # FamilyWild for display 0 and for any display; xauth add cannot write them.
        xauth(
            source,
            "nmerge",
            "-",
            stdin=(
                f"ffff 0000  0001 30 {len(MIT):04x} {mit} 0010 {'44' * 16}\n"
                f"ffff 0000  0000  {len(MIT):04x} {mit} 0010 {'55' * 16}\n"
                f"ffff 0000  0001 37 {len(MIT):04x} {mit} 0010 {'66' * 16}\n"
            ),
        )
        expected = sorted(
            line
            for line in xauth(source, "nlist").splitlines()
            if any(cookie in line for cookie in ("00" * 16, "44" * 16, "55" * 16))
        )
        self.assertEqual(len(expected), 3)
        out = self.tmp / "out"
        out.write_bytes(display.entries_for(source.read_bytes(), 0, self.host))
        self.assertEqual(sorted(xauth(out, "nlist").splitlines()), expected)

    def test_a_truncated_tail_ends_the_records(self) -> None:
        """A record cut short is dropped, and the ones before it stay, as XauReadAuth reads."""
        source = self.tmp / "source"
        xauth(source, "add", f"{self.host}/unix:3", MIT, "ab" * 16)
        whole = source.read_bytes()
        for cut in (1, 5, len(whole) - 1):
            with self.subTest(cut=cut):
                data = whole + whole[:cut]
                self.assertEqual(display.entries_for(data, 3, self.host), whole)


class LocalDisplayTest(unittest.TestCase):
    """Which DISPLAY values name a display the namespace can reach."""

    def setUp(self) -> None:
        """A socket directory with display 5's socket and a plain file for display 7."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-display-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        server = listening_socket(self.tmp / "X5")
        self.addCleanup(server.close)
        (self.tmp / "X7").write_text("")
        patch = unittest.mock.patch.object(display, "SOCKET_DIR", self.tmp)
        patch.start()
        self.addCleanup(patch.stop)

    def test_local_names(self) -> None:
        """:N, :N.S and unix:N reach the socket file; the screen stays in the name."""
        for name, expected in ((":5", ":5"), (":5.1", ":5.1"), ("unix:5", ":5")):
            with self.subTest(name):
                screen = display.local_display({"DISPLAY": name})
                self.assertEqual((screen.name, screen.socket), (expected, self.tmp / "X5"))

    def test_refused_names(self) -> None:
        """No DISPLAY, a remote or TCP one, or one without a socket file is an error."""
        for name, reason in (
            ("", "DISPLAY is not set"),
            ("other.example:0", "not a local display"),
            ("localhost:10.0", "not a local display"),
            (":6", "no socket"),
            (":7", "no socket"),
        ):
            with self.subTest(name), self.assertRaisesRegex(display.DisplayError, reason):
                display.local_display({"DISPLAY": name} if name else {})

    def test_the_authority_file_xlib_reads(self) -> None:
        """XAUTHORITY wins over ~/.Xauthority; a missing file is no records."""
        record = display.AuthEntry(display.FAMILY_WILD, b"", b"5", MIT.encode(), b"k" * 16)
        (self.tmp / ".Xauthority").write_bytes(record.encode())
        home = {"DISPLAY": ":5", "HOME": str(self.tmp)}
        self.assertEqual(display.local_display(home).authority, record.encode())
        named = {**home, "XAUTHORITY": str(self.tmp / "missing")}
        self.assertEqual(display.local_display(named).authority, b"")


class FakeLogin:
    """Stands in for Camoufox in the command line: records the login, holds canned cookies."""

    def __init__(self, profile: Path) -> None:
        """No login yet."""
        self.profile = profile
        self.logins: list[tuple[str, display.Display]] = []
        self.warnings: list[str] = []
        self.cookies: list[jar.Cookie] = []

    def login(self, url: str, screen: display.Display, until: float) -> list[str]:  # noqa: ARG002
        """Record the call."""
        self.logins.append((url, screen))
        return list(self.warnings)

    def jar(self, until: float) -> list[jar.Cookie]:  # noqa: ARG002
        """The canned cookies."""
        return self.cookies


class LoginCliTest(unittest.TestCase):
    """browser-fetch login's arguments, output and exit codes."""

    def setUp(self) -> None:
        """A display 5 socket, a runtime directory, and the stand-in browser."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-login-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        (self.tmp / "x11").mkdir()
        (self.tmp / "runtime").mkdir(mode=0o700)
        server = listening_socket(self.tmp / "x11" / "X5")
        self.addCleanup(server.close)
        self.fake = FakeLogin(self.tmp / "profile")
        env = {
            "DISPLAY": ":5",
            "XAUTHORITY": str(self.tmp / "none"),
            "XDG_RUNTIME_DIR": str(self.tmp / "runtime"),
        }
        for patch in (
            unittest.mock.patch.dict(os.environ, env),
            unittest.mock.patch.object(display, "SOCKET_DIR", self.tmp / "x11"),
            unittest.mock.patch.object(cli, "camoufox", return_value=self.fake),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def run_main(self, *argv: str) -> tuple[int, str, str]:
        """Run main and return its status, stdout and stderr."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = cli.main(list(argv))
        return status, out.getvalue(), err.getvalue()

    def test_without_a_url_it_opens_kagis_sign_in(self) -> None:
        """The default page is Kagi's sign-in page, on the display DISPLAY names."""
        status, _, _ = self.run_main("login")
        self.assertEqual(status, 0)
        ((url, screen),) = self.fake.logins
        self.assertEqual(url, "https://kagi.com/signin")
        self.assertEqual((screen.name, screen.socket), (":5", self.tmp / "x11" / "X5"))

    def test_any_http_url_goes_as_given(self) -> None:
        """Any http or https URL is opened as written, local and private hosts included."""
        for url in (
            "https://example.org/a?b=c",
            "http://example.org/",
            "http://localhost:3000/",
            "http://192.168.1.10:8080/x",
        ):
            with self.subTest(url):
                self.fake.logins.clear()
                self.assertEqual(self.run_main("login", url)[0], 0)
                self.assertEqual([u for u, _ in self.fake.logins], [url])

    def test_other_arguments_are_usage_errors(self) -> None:
        """Anything but an http or https URL with a host exits 2 and opens nothing."""
        for url in ("ftp://example.org/", "example.org", "https://", "https://[::1/"):
            with self.subTest(url):
                status, out, err = self.run_main("login", url)
                self.assertEqual((status, out), (cli.USAGE_EXIT, ""))
                self.assertEqual(err, f"browser-fetch: not an http or https URL: {url}\n")
        self.assertEqual(self.fake.logins, [])

    def test_no_display_exits_5(self) -> None:
        """Without a local display the browser cannot open its window."""
        with unittest.mock.patch.dict(os.environ, {"DISPLAY": ""}):
            status, _, err = self.run_main("login")
        self.assertEqual(status, cli.BROWSER_EXIT)
        self.assertIn("DISPLAY is not set", err)
        self.assertEqual(self.fake.logins, [])

    def test_it_reports_the_cookies_it_left_and_the_warnings(self) -> None:
        """The cookies the site's URL now gets are counted; warnings go to stderr."""
        later = jar.now_us() // 1000 + 86_400_000
        self.fake.cookies = [
            jar.Cookie("a", "1", "kagi.com", "/", later, secure=True, created=1),
            jar.Cookie("b", "2", ".kagi.com", "/", later, secure=True, created=2),
            jar.Cookie("c", "3", "example.org", "/", later, secure=True, created=3),
        ]
        self.fake.warnings = ["the browser did not close cleanly"]
        status, out, err = self.run_main("login")
        self.assertEqual(status, 0)
        database = self.tmp / "profile" / jar.DB_NAME
        self.assertEqual(out, f"2 cookies for kagi.com are in {database}\n")
        self.assertIn("browser-fetch: warning: the browser did not close cleanly\n", err)

    def test_no_work_directory_is_left(self) -> None:
        """The run's work directory, which held the Xauthority copy, goes with it."""
        self.run_main("login")
        self.assertEqual(list((self.tmp / "runtime").iterdir()), [])

    def test_help(self) -> None:
        """Login has its own help, and the fetch's help names it."""
        for argv, text in ((["login", "--help"], "browser-fetch login"), (["--help"], "login")):
            with self.subTest(argv), contextlib.redirect_stdout(io.StringIO()) as out:
                with self.assertRaises(SystemExit) as stop:
                    cli.main(argv)
                self.assertEqual(stop.exception.code, 0)
                self.assertIn(text, out.getvalue())


class CamoufoxLoginTest(unittest.TestCase):
    """browser.Camoufox.login with the session replaced."""

    def setUp(self) -> None:
        """A state directory with a fingerprint, a work directory and a display."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-login-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.state = self.tmp / "state"
        self.state.mkdir(mode=0o700)
        self.work = self.tmp / "work"
        self.work.mkdir()
        fingerprint = {"browser": VERSION, "headers": {"user-agent": "UA", "accept-language": "en"}}
        (self.state / browser.FINGERPRINT).write_text(json.dumps(fingerprint))
        self.screen = display.Display(":5", Path("/tmp/.X11-unix/X5"), b"records")  # noqa: S108
        self.camoufox = browser.Camoufox(
            browser.Tools("unshare", "session", VERSION, "pasta"), self.state, self.work
        )

    def test_the_session_gets_the_shared_profile_and_the_display(self) -> None:
        """One login session on the persistent profile, with the display's socket and records."""
        seen: list[tuple[str, dict[str, Any], bytes, int]] = []

        def session(
            _self: browser.Camoufox, mode: str, request: dict[str, Any], _until: float
        ) -> dict[str, Any]:
            authority = Path(request["xauthority"])
            seen.append((mode, request, authority.read_bytes(), authority.stat().st_mode & 0o777))
            return {"closed": True, "warnings": ["w"]}

        with unittest.mock.patch.object(browser.Camoufox, "_session", autospec=True) as patched:
            patched.side_effect = session
            warnings = self.camoufox.login(
                "https://example.org/", self.screen, time.monotonic() + 30
            )
        ((mode, request, records, mode_bits),) = seen
        self.assertEqual(mode, "login")
        self.assertEqual(request["profile"], str(self.state / browser.PROFILE))
        self.assertEqual(request["url"], "https://example.org/")
        self.assertEqual((request["display"], request["socket"]), (":5", "/tmp/.X11-unix/X5"))  # noqa: S108
        self.assertEqual(Path(request["xauthority"]).parent, self.work)
        self.assertEqual((records, mode_bits), (b"records", 0o600))
        self.assertEqual(warnings, ["w"])

    def test_the_profile_stays_locked_while_the_window_is_open(self) -> None:
        """A fetch's jar read meanwhile waits its short bound, then reports the busy profile."""
        (self.state / browser.PROFILE).mkdir()
        (self.state / browser.PROFILE / jar.DB_NAME).touch()
        other = browser.Camoufox(
            browser.Tools("unshare", "session", VERSION, "pasta"), self.state, self.tmp
        )
        outcome: dict[str, Any] = {}

        def session(
            _self: browser.Camoufox, _mode: str, _request: dict[str, Any], _until: float
        ) -> dict[str, Any]:
            started = time.monotonic()
            try:
                other.jar(time.monotonic() + 60)
            except browser.BrowserError as error:
                outcome["error"] = str(error)
            outcome["waited"] = time.monotonic() - started
            return {"closed": True, "warnings": []}

        with unittest.mock.patch.object(browser.Camoufox, "_session", autospec=True) as patched:
            patched.side_effect = session
            self.camoufox.login("https://example.org/", self.screen, time.monotonic() + 30)
        self.assertIn("busy", outcome["error"])
        self.assertGreaterEqual(outcome["waited"], browser.JAR_LOCK_SECONDS)
        self.assertLess(outcome["waited"], browser.JAR_LOCK_SECONDS + 3)
        # Released afterwards.
        self.assertEqual(other.jar(time.monotonic() + 5), [])

    def test_a_busy_profile_fails_within_the_bound(self) -> None:
        """A render holding the profile keeps the login from starting, and it says so."""
        holder = os.open(self.state / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, holder)
        fcntl.flock(holder, fcntl.LOCK_EX)
        with (
            unittest.mock.patch.object(browser.Camoufox, "_session") as session,
            self.assertRaisesRegex(browser.BrowserError, "busy"),
        ):
            self.camoufox.login("https://example.org/", self.screen, time.monotonic() + 0.5)
        session.assert_not_called()


# The session's steps of a login up to the browser, with a display socket bound in.
BIND_PROBE = """\
import os, socket, sys
from pathlib import Path
from browser_fetch import browser, session
work = Path(sys.argv[1])
target = Path(os.environ["PROBE_SOCKET"])
(work / browser.NETWORK_READY).write_text("")
import time
until = time.monotonic() + 20
session.private_tmp([work], [target])
session.await_network(work, until)
session.loopback_up()
session.drop_capabilities()
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.connect(str(target))
client.sendall(b"ping")
client.close()
print(sorted(os.listdir(target.parent)))
"""


class DisplaySocketTest(unittest.TestCase):
    """The namespace reaches the display's socket file and nothing else of /tmp."""

    @classmethod
    def setUpClass(cls) -> None:
        """Skip, saying why, where the host cannot make the session's namespace."""
        require_namespaces()

    def test_only_the_displays_socket_is_bound_in(self) -> None:
        """A connection over the bound socket arrives; a sibling socket and file stay out."""
        outside = Path(tempfile.mkdtemp(prefix="browser-fetch-x11-", dir="/tmp"))
        self.addCleanup(shutil.rmtree, outside)
        server = listening_socket(outside / "X0")
        self.addCleanup(server.close)
        sibling = listening_socket(outside / "X1")
        self.addCleanup(sibling.close)
        (outside / "secret").write_text("no")
        received: list[bytes] = []

        def accept() -> None:
            connection, _ = server.accept()
            with connection:
                received.append(connection.recv(16))

        thread = threading.Thread(target=accept, daemon=True)
        thread.start()
        with (
            tempfile.TemporaryDirectory(prefix="browser-fetch-probe-") as work,
            unittest.mock.patch.dict(os.environ, {"PROBE_SOCKET": str(outside / "X0")}),
        ):
            ran = run_in_namespace(BIND_PROBE, Path(work))
        self.assertEqual(ran.returncode, 0, ran.stderr)
        thread.join(5)
        self.assertEqual(received, [b"ping"])
        self.assertEqual(ran.stdout.strip(), "['X0']")


class _ClientMessage(ctypes.Structure):
    _fields_: ClassVar = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
        ("message_type", ctypes.c_ulong),
        ("format", ctypes.c_int),
        ("data", ctypes.c_long * 5),
    ]


class _Event(ctypes.Union):
    _fields_: ClassVar = [("client", _ClientMessage), ("pad", ctypes.c_long * 24)]


def close_window(window: int) -> None:
    """Send WM_DELETE_WINDOW to window, as a window manager's close button does (ICCCM 4.2.8.1)."""
    x11 = ctypes.CDLL(LIBX11)
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XInternAtom.restype = ctypes.c_ulong
    x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x11.XSendEvent.argtypes = [
        ctypes.c_void_p,
        ctypes.c_ulong,
        ctypes.c_int,
        ctypes.c_long,
        ctypes.POINTER(_Event),
    ]
    x11.XFlush.argtypes = [ctypes.c_void_p]
    x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
    connection = x11.XOpenDisplay(None)
    if not connection:
        msg = "the test could not open the display"
        raise OSError(msg)
    try:
        event = _Event()
        event.client.type = 33  # ClientMessage
        event.client.window = window
        event.client.message_type = x11.XInternAtom(connection, b"WM_PROTOCOLS", 0)
        event.client.format = 32
        event.client.data[0] = x11.XInternAtom(connection, b"WM_DELETE_WINDOW", 0)
        x11.XSendEvent(connection, window, 0, 0, ctypes.byref(event))
        x11.XFlush(connection)
    finally:
        x11.XCloseDisplay(connection)


# A session whose a.test serves one page on the namespace's loopback: it sets
# a persistent and a session cookie by header, then the same by script, and
# only then takes the title the test waits for.
LOGIN_SESSION = """\
import http.server, sys, threading
sys.path.insert(0, {root!r})
from browser_fetch import session
PAGE = (
    b"<!DOCTYPE html><title>loading</title><script>"
    b"document.cookie = 'script=1; max-age=3600; path=/';"
    b"document.cookie = 'fleeting=1; path=/';"
    b"document.title = 'login-ready';</script><p>sign in here</p>"
)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Set-Cookie", "header=1; Max-Age=3600; Path=/")
        self.send_header("Set-Cookie", "sess=1; Path=/")
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, *args):
        return

loopback_up = session.loopback_up

def loopback_then_serve():
    loopback_up()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", {port}), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

session.loopback_up = loopback_then_serve
sys.exit(session.main(sys.argv[1:]))
"""
LOGIN_PORT = 8767


@unittest.skipUnless(
    XAUTH and XWININFO and LIBX11, "the X test tools are not named in the environment"
)
class RealLoginTest(unittest.TestCase):
    """Real Camoufox on an X server that demands its cookie, closed as a window manager would."""

    @classmethod
    def setUpClass(cls) -> None:
        """Skip, saying why, where the host cannot make the session's namespace."""
        require_namespaces()

    def setUp(self) -> None:
        """An X server with a cookie, the state, the stand-in pasta and the serving session."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-login-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.number = next(
            n
            for n in range(140, 400)
            if not (display.SOCKET_DIR / f"X{n}").exists() and not Path(f"/tmp/.X{n}-lock").exists()  # noqa: S108
        )
        self.authority = self.tmp / "xauthority"
        xauth(self.authority, "add", f":{self.number}", MIT, secrets.token_hex(16))
        xvfb = subprocess.Popen(
            [
                tools.XVFB,
                f":{self.number}",
                "-auth",
                str(self.authority),
                "-nolisten",
                "tcp",
                "-screen",
                "0",
                "1280x800x24",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"PATH": "/var/empty"},
        )
        self.addCleanup(xvfb.wait)
        self.addCleanup(xvfb.terminate)
        give_up = time.monotonic() + 30
        while not (display.SOCKET_DIR / f"X{self.number}").exists():
            if xvfb.poll() is not None or time.monotonic() > give_up:
                self.fail("Xvfb did not start")
            time.sleep(0.1)
        self.env = {"DISPLAY": f":{self.number}", "XAUTHORITY": str(self.authority)}
        self.state = self.tmp / "state"
        self.work = self.tmp / "work"
        self.work.mkdir()
        script = self.tmp / "session"
        script.write_text(
            f"#!{sys.executable} -I\n" + LOGIN_SESSION.format(root=ROOT, port=LOGIN_PORT)
        )
        script.chmod(0o700)
        self.camoufox = browser.Camoufox(
            tools_with(write_fake_pasta(self.tmp), str(script)), self.state, self.work, environ={}
        )

    def x(self, tool: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        """Run an X client on the test's display."""
        return subprocess.run(
            [tool, *args],
            capture_output=True,
            text=True,
            check=check,
            # The browser's titles end in an em dash, which C's charset cannot convert.
            env={"PATH": "/var/empty", "LC_ALL": "C.UTF-8", **self.env},
            timeout=30,
        )

    def window(self, title: str, until: float) -> tuple[str, str] | None:
        """The id and class of the top-level window whose title starts with title, once there."""
        while time.monotonic() < until:
            tree = self.x(XWININFO, "-root", "-children", check=False).stdout
            for line in tree.splitlines():
                found = re.match(r'\s*(0x[0-9a-f]+) "(.*)": \("[^"]*" "([^"]*)"\)', line)
                if found and found.group(2).startswith(title):
                    return found.group(1), found.group(3)
            time.sleep(0.5)
        return None

    def test_a_window_on_the_display_whose_cookies_reach_the_jar(self) -> None:
        """The page opens visibly on DISPLAY; closing it puts its persistent cookies in the jar."""
        # The server demands the cookie: a client without it is refused.
        refused = subprocess.run(
            [XWININFO, "-root"],
            capture_output=True,
            env={
                "PATH": "/var/empty",
                "DISPLAY": self.env["DISPLAY"],
                "XAUTHORITY": "/var/empty/x",
            },
            check=False,
            timeout=30,
        )
        self.assertNotEqual(refused.returncode, 0)
        if self.camoufox.identity(time.monotonic() + 120) is None:
            self.fail("no fingerprint was drawn")
        fingerprint_path = self.state / browser.FINGERPRINT
        fingerprint = json.loads(fingerprint_path.read_text())
        fingerprint["prefs"]["network.dns.localDomains"] = "a.test"
        fingerprint_path.write_text(json.dumps(fingerprint))

        screen = display.local_display({**self.env, "HOME": str(self.tmp)})
        outcome: dict[str, Any] = {}

        def login() -> None:
            try:
                outcome["warnings"] = self.camoufox.login(
                    f"http://a.test:{LOGIN_PORT}/", screen, time.monotonic() + 180
                )
            except Exception as error:  # noqa: BLE001 - reported by the test
                outcome["error"] = error

        thread = threading.Thread(target=login, daemon=True)
        thread.start()
        shown = self.window("login-ready", time.monotonic() + 120)
        if shown is None:
            thread.join(1)
            log = (self.work / "session.log").read_text(errors="replace")[-2000:]
            self.fail(f"no window appeared: {outcome.get('error')}; session log: {log}")
        window, window_class = shown
        self.assertEqual(window_class, "camoufox")
        self.assertIn("Map State: IsViewable", self.x(XWININFO, "-id", window).stdout)
        # The profile is the one fetches use, and it is held.
        with self.assertRaisesRegex(browser.BrowserError, "busy"):
            browser.Camoufox(self.camoufox.tools, self.state, self.tmp).jar(time.monotonic() + 30)
        with unittest.mock.patch.dict(os.environ, self.env):
            close_window(int(window, 16))
        thread.join(60)
        self.assertFalse(thread.is_alive(), "the login did not end when its window closed")
        self.assertNotIn("error", outcome, outcome.get("error"))
        self.assertEqual(outcome["warnings"], [])
        self.assertIsNone(self.window("login-ready", time.monotonic() + 2))
        db = sqlite3.connect(self.state / browser.PROFILE / jar.DB_NAME)
        try:
            rows = dict(db.execute("select name, host from moz_cookies").fetchall())
        finally:
            db.close()
        self.assertEqual(rows, {"header": "a.test", "script": "a.test"})
