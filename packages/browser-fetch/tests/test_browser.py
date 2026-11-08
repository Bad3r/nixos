# Copyright (c) 2026 Bad3r
"""The Camoufox fallback: identity, lock, the cookie jar around a render, cleanup, real runs."""

import fcntl
import json
import os
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from browser_fetch import browser, curl, fetch, tools
from browser_fetch import cookies as jar

from tests.fakes import fake_curl, public
from tests.namespaces import ROOT, require_namespaces, tools_with, write_fake_pasta

VERSION = "158.0.1-beta.41"
URL = "https://a.example/"


def values(path: Path) -> dict[str, str]:
    """The jar's cookies by name; none without a database."""
    if not path.exists():
        return {}
    db = sqlite3.connect(path)
    try:
        return dict(db.execute("select name, value from moz_cookies").fetchall())
    finally:
        db.close()


def received(*lines: str, url: str = URL, stored: list[jar.Cookie] | None = None) -> jar.Jar:
    """A fetch's jar after a response for url set the given cookies."""
    cookies = jar.Jar.of(stored or [])
    cookies.receive(url, lines, jar.now_us(), None)
    return cookies


class CamoufoxTest(unittest.TestCase):
    """browser.Camoufox with the session replaced."""

    def setUp(self) -> None:
        """A state and a work directory."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        self.state = self.tmp / "state"
        self.work = self.tmp / "work"
        self.work.mkdir()
        self.sessions: list[tuple[str, dict[str, Any]]] = []

    def tearDown(self) -> None:
        """Remove both."""
        shutil.rmtree(self.tmp)

    def camoufox(self, version: str = VERSION) -> browser.Camoufox:
        """A Camoufox for the release version."""
        return browser.Camoufox(
            browser.Tools("unshare", "session", version, "pasta"), self.state, self.work
        )

    def fake_session(
        self, _camoufox: browser.Camoufox, mode: str, request: dict[str, Any], until: float
    ) -> dict[str, Any]:
        """Bound to the patched method's receiver."""
        return self.generate(mode, request, until)

    def generate(self, mode: str, request: dict[str, Any], until: float) -> dict[str, Any]:  # noqa: ARG002
        """Stand in for session.py's generate mode."""
        self.sessions.append((mode, request))
        fingerprint = {
            "browser": VERSION,
            "headers": {"user-agent": f"UA-{len(self.sessions)}", "accept-language": "en-US"},
        }
        (self.state / browser.FINGERPRINT).write_text(json.dumps(fingerprint))
        return {"generated": True}

    def test_fingerprint_is_generated_once_and_kept(self) -> None:
        """The first fetch draws the identity; later fetches, in new processes too, reuse it."""
        with unittest.mock.patch.object(browser.Camoufox, "_session", autospec=True) as session:
            session.side_effect = self.fake_session
            first = self.camoufox().identity(time.monotonic() + 30)
            again = self.camoufox().identity(time.monotonic() + 30)
        self.assertEqual(first, again)
        self.assertEqual(first, curl.Identity("UA-1", "en-US"))
        self.assertEqual([mode for mode, _ in self.sessions], ["generate"])
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)

    def test_new_release_draws_a_new_fingerprint(self) -> None:
        """A fingerprint of another browser release is not reused."""
        (self.state).mkdir(mode=0o700)
        (self.state / browser.FINGERPRINT).write_text(
            json.dumps({"browser": "157.0-beta.1", "headers": {}})
        )
        with unittest.mock.patch.object(browser.Camoufox, "_session", autospec=True) as session:
            session.side_effect = self.fake_session
            self.camoufox().identity(time.monotonic() + 30)
        self.assertEqual(len(self.sessions), 1)

    def test_no_fingerprint_is_drawn_unless_asked(self) -> None:
        """A fetch that will not run the browser reads a fingerprint but never draws one."""
        with unittest.mock.patch.object(browser.Camoufox, "_session", autospec=True) as session:
            self.assertIsNone(self.camoufox().identity(time.monotonic() + 30, generate=False))
            session.assert_not_called()
        self.assertFalse(self.state.exists())

    def test_unusable_state_is_a_browser_error(self) -> None:
        """A state directory that cannot be created is the browser's failure, not an OSError."""
        blocked = self.tmp / "read-only"
        blocked.mkdir(mode=0o500)
        camoufox = browser.Camoufox(
            browser.Tools("unshare", "session", VERSION, "pasta"), blocked / "state", self.work
        )
        with self.assertRaisesRegex(browser.BrowserError, "unusable"):
            camoufox.identity(time.monotonic() + 30)

    def test_profile_lock_wait_is_bounded(self) -> None:
        """A second fallback waits for the profile, then gives up within its bound."""
        self.state.mkdir(mode=0o700)
        holder = os.open(self.state / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(holder, fcntl.LOCK_EX)
        try:
            started = time.monotonic()
            with (
                unittest.mock.patch.object(browser.Camoufox, "_session") as session,
                self.assertRaisesRegex(browser.BrowserError, "busy"),
            ):
                self.camoufox().render(URL, jar.Jar(), time.monotonic() + 0.5)
            session.assert_not_called()
            self.assertLess(time.monotonic() - started, 5)
        finally:
            os.close(holder)

    def test_jar_read_waits_only_briefly_for_a_busy_profile(self) -> None:
        """A jar read gives up after JAR_LOCK_SECONDS, not the render's LOCK_SECONDS."""
        self.database().parent.mkdir(parents=True)
        self.database().touch()
        holder = os.open(self.state / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(holder, fcntl.LOCK_EX)
        self.addCleanup(os.close, holder)
        started = time.monotonic()
        with self.assertRaisesRegex(browser.BrowserError, "busy"):
            self.camoufox().jar(time.monotonic() + 60)
        elapsed = time.monotonic() - started
        self.assertGreaterEqual(elapsed, browser.JAR_LOCK_SECONDS)
        self.assertLess(elapsed, browser.JAR_LOCK_SECONDS + 3)

    def database(self) -> Path:
        """The profile's cookie database."""
        return self.state / browser.PROFILE / jar.DB_NAME

    def render_seeing(self, cookies: jar.Jar, *, keep: bool = True) -> dict[str, Any]:
        """Render with a session that records the profile and the cookies it was handed."""
        seen: dict[str, Any] = {}

        def session(
            _self: browser.Camoufox, _mode: str, request: dict[str, Any], _until: float
        ) -> dict[str, Any]:
            seen["profile"] = request["profile"]
            seen["jar"] = values(Path(request["profile"]) / jar.DB_NAME)
            seen["handed"] = request["cookies"]
            (self.work / "page.html").write_text("<p>ok</p>")
            return {"url": URL, "status": 200, "contentType": "text/html", "html": True}

        with unittest.mock.patch.object(browser.Camoufox, "_session", autospec=True) as patched:
            patched.side_effect = session
            self.camoufox().render(URL, cookies, time.monotonic() + 30, keep=keep)
        return seen

    def test_curls_cookies_are_in_the_profile_when_the_browser_starts(self) -> None:
        """The fetch's changes reach the database first; its session cookies are handed over.

        A deletion removes the stored row, and a partitioned session cookie
        stays out, since Playwright adds to the unpartitioned jar only.
        """
        jar.store(
            self.database(),
            [
                jar.parse_set_cookie(c, URL, jar.now_us())
                for c in ("gone=1; Max-Age=600", "kept=1; Max-Age=600")
            ],  # type: ignore[misc]
            jar.now_us(),
        )
        cookies = received(
            "persisted=curl; Max-Age=600; Secure",
            "sess=curl; Secure; HttpOnly; SameSite=Lax",
            "chips=curl; Secure; Partitioned",
            "gone=; Max-Age=0",
            stored=jar.read(self.database()),
        )
        seen = self.render_seeing(cookies)
        self.assertEqual(seen["profile"], str(self.state / browser.PROFILE))
        self.assertEqual(seen["jar"], {"kept": "1", "persisted": "curl"})
        self.assertEqual(
            seen["handed"],
            [
                {
                    "name": "sess",
                    "value": "curl",
                    "domain": "a.example",
                    "path": "/",
                    "expires": -1,
                    "httpOnly": True,
                    "secure": True,
                    "sameSite": "Lax",
                }
            ],
        )
        self.assertEqual(cookies.unsaved, {})

    def test_a_busy_profile_writes_nothing(self) -> None:
        """A render that cannot take the lock leaves the changes unsaved for the fetch to report."""
        self.state.mkdir(mode=0o700)
        holder = os.open(self.state / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(holder, fcntl.LOCK_EX)
        self.addCleanup(os.close, holder)
        cookies = received("persisted=curl; Max-Age=600")
        with self.assertRaisesRegex(browser.BrowserError, "busy"):
            self.camoufox().render(URL, cookies, time.monotonic() + 0.5)
        with (
            unittest.mock.patch.object(browser, "JAR_LOCK_SECONDS", 0.3),
            self.assertRaisesRegex(browser.BrowserError, "busy"),
        ):
            self.camoufox().store(cookies, time.monotonic() + 30)
        self.assertEqual(len(cookies.unsaved), 1)
        self.assertFalse(self.database().exists())

    def test_without_cookies_the_profile_is_thrown_away(self) -> None:
        """--no-cookies renders in the work directory, unlocked, handed every live cookie."""
        self.state.mkdir(mode=0o700)
        holder = os.open(self.state / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(holder, fcntl.LOCK_EX)
        self.addCleanup(os.close, holder)
        cookies = received("persisted=curl; Max-Age=600", "sess=curl")
        (self.work / browser.PROFILE).mkdir()
        seen = self.render_seeing(cookies, keep=False)
        self.assertEqual(seen["profile"], str(self.work / browser.PROFILE))
        self.assertEqual(sorted(c["name"] for c in seen["handed"]), ["persisted", "sess"])
        self.assertTrue(all(c["expires"] == -1 for c in seen["handed"]))
        self.assertFalse(self.database().exists())

    def test_schema_mismatch_starts_no_browser(self) -> None:
        """A database at another version is refused before the browser starts."""
        self.database().parent.mkdir(parents=True)
        db = sqlite3.connect(self.database())
        db.execute("pragma user_version = 18")
        db.close()
        with (
            unittest.mock.patch.object(browser.Camoufox, "_session") as session,
            self.assertRaisesRegex(jar.CookieError, "schema version 18"),
        ):
            self.camoufox().render(URL, received("a=1; Max-Age=60"), time.monotonic() + 30)
        session.assert_not_called()

    def script(self, name: str, body: str) -> str:
        """An executable stand-in in the test directory."""
        path = self.tmp / name
        path.write_text(f"#!{sys.executable} -I\n{body}")
        path.chmod(0o700)
        return str(path)

    def test_unavailable_namespaces_fail_at_once(self) -> None:
        """Unshare refused by the host is a browser failure naming why, not a wait."""
        unshare = self.script(
            "unshare",
            "import sys\n"
            "print('unshare: unshare failed: Operation not permitted', flush=True)\n"
            "sys.exit(1)\n",
        )
        camoufox = browser.Camoufox(
            browser.Tools(unshare, "session", VERSION, "pasta"), self.state, self.work
        )
        self.state.mkdir(mode=0o700)
        started = time.monotonic()
        with self.assertRaisesRegex(browser.BrowserError, "Operation not permitted"):
            camoufox.render(URL, jar.Jar(), time.monotonic() + 60)
        self.assertLess(time.monotonic() - started, 5)

    def test_pasta_failure_fails_the_session(self) -> None:
        """A namespace pasta cannot connect is a browser failure, and nothing is left running."""
        unshare = self.script(
            "unshare",
            "import sys, time\n"
            "from pathlib import Path\n"
            f"Path({str(self.work)!r}, 'netns.ready').write_text('')\n"
            "time.sleep(600)\n",
        )
        pasta = self.script(
            "pasta", "import sys\nprint('Failed to open() /dev/net/tun', flush=True)\nsys.exit(1)\n"
        )
        camoufox = browser.Camoufox(
            browser.Tools(unshare, "session", VERSION, pasta), self.state, self.work
        )
        self.state.mkdir(mode=0o700)
        started = time.monotonic()
        with self.assertRaisesRegex(browser.BrowserError, "network could not be set up.*tun"):
            camoufox.render(URL, jar.Jar(), time.monotonic() + 60)
        self.assertLess(time.monotonic() - started, 10)
        self.assertFalse((self.work / browser.NETWORK_READY).exists())

    def test_session_keeps_curls_proxy_variables(self) -> None:
        """The session gets each variable curl reads its proxy from, and no other of the user's."""
        environ = {
            "HOME": "/home/u",
            "DISPLAY": ":0",
            "all_proxy": "socks5h://a.example:1080",
            "ALL_PROXY": "socks5h://b.example:1080",
            "https_proxy": "http://c.example:3128",
            "HTTPS_PROXY": "http://d.example:3128",
            "no_proxy": "e.example",
        }
        camoufox = browser.Camoufox(
            browser.Tools("unshare", "session", VERSION, "pasta"),
            self.state,
            self.work,
            environ=environ,
        )
        kept: dict[str, str] = {}

        class StartedError(Exception):
            """The session's launch, stopped once its environment is seen."""

        def popen(*_args: Any, **options: Any) -> None:  # noqa: ANN401
            kept.update(options["env"])
            raise StartedError

        with (
            unittest.mock.patch.object(browser.subprocess, "Popen", side_effect=popen),
            self.assertRaises(StartedError),
        ):
            camoufox.render(URL, jar.Jar(), time.monotonic() + 30)
        del environ["HOME"], environ["DISPLAY"]
        self.assertEqual(kept, {**environ, "PATH": "/var/empty"})

    def test_playwright_cookie(self) -> None:
        """A session cookie in Gecko's host form; None and unset go without SameSite.

        Juggler's setCookies stores SameSite None and an absent one alike as
        unset (TargetRegistry.js), so only Lax and Strict are passed.
        """
        host_only = jar.Cookie("a", "1", "a.example", "/p", 1, secure=False, created=1)
        domain = jar.Cookie(
            "b", "2", ".a.example", "/", 1, secure=True, created=1, same_site=jar.SAME_SITE_STRICT
        )
        self.assertEqual(
            browser.playwright_cookie(host_only),
            {
                "name": "a",
                "value": "1",
                "domain": "a.example",
                "path": "/p",
                "expires": -1,
                "httpOnly": False,
                "secure": False,
            },
        )
        self.assertEqual(
            (
                browser.playwright_cookie(domain)["domain"],
                browser.playwright_cookie(domain)["sameSite"],
            ),
            (".a.example", "Strict"),
        )


FAKE_SESSION = """\
import json, os, subprocess, sys, time
sys.path.insert(0, {root!r})
from pathlib import Path
from browser_fetch import session
request = json.loads(Path(sys.argv[1]).read_text())
workdir = Path(request["workdir"])
session.private_tmp([workdir, Path(request["state"])])
session.await_network(workdir, time.monotonic() + 30)
session.confine_network()
session.drop_capabilities()
xvfb, display = session.start_xvfb(time.monotonic() + 30)
child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"])
ready = {{"ns": os.readlink("/proc/self/ns/pid"), "display": display}}
(workdir / "ready").write_text(json.dumps(ready))
time.sleep(600)
"""

PARENT = """\
import signal, sys, time
sys.path.insert(0, {root!r})
from pathlib import Path
from browser_fetch import browser
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
tools = browser.Tools({unshare!r}, {session!r}, "v", {pasta!r})
camoufox = browser.Camoufox(tools, Path({state!r}), Path({work!r}))
try:
    camoufox._session("render", {{}}, time.monotonic() + {seconds})
except browser.BrowserError as error:
    print(error, flush=True)
    sys.exit(5)
"""


def _x_files() -> set[str]:
    found = {str(p) for p in Path("/tmp").glob(".X*-lock")}  # noqa: S108 - the host's X files
    sockets = Path("/tmp/.X11-unix")  # noqa: S108
    if sockets.is_dir():
        found |= {str(p) for p in sockets.iterdir()}
    return found


def _running(path: str) -> list[int]:
    """The processes whose command line names path."""
    pids: list[int] = []
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                if path.encode() in (entry / "cmdline").read_bytes():
                    pids.append(int(entry.name))
            except OSError:
                continue
    return pids


def _in_namespace(ns: str) -> list[int]:
    pids: list[int] = []
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                if str((entry / "ns" / "pid").readlink()) == ns:
                    pids.append(int(entry.name))
            except OSError:
                continue
    return pids


class CleanupTest(unittest.TestCase):
    """No process, X socket or lock file outlives browser-fetch, however it ends."""

    @classmethod
    def setUpClass(cls) -> None:
        """Skip, saying why, where the host cannot make the session's namespace."""
        require_namespaces()

    def setUp(self) -> None:
        """A state and work directory and the stand-in session executable."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        self.work = self.tmp / "work"
        self.work.mkdir()
        root = str(Path(__file__).resolve().parents[1])
        self.session = self.tmp / "session"
        self.session.write_text(f"#!{sys.executable} -I\n" + FAKE_SESSION.format(root=root))
        self.session.chmod(0o700)
        self.root = root
        self.pasta = write_fake_pasta(self.tmp)
        self.x_before = _x_files()

    def tearDown(self) -> None:
        """Remove the directories."""
        shutil.rmtree(self.tmp)

    def start(self, seconds: float) -> subprocess.Popen[str]:
        """Start a stand-in browser-fetch running one session."""
        script = PARENT.format(
            root=self.root,
            unshare=tools.UNSHARE,
            session=str(self.session),
            pasta=self.pasta,
            state=str(self.tmp / "state"),
            work=str(self.work),
            seconds=seconds,
        )
        return subprocess.Popen(
            [sys.executable, "-I", "-c", script], stdout=subprocess.PIPE, text=True
        )

    def ready(self) -> dict[str, str]:
        """Wait for the session to report its namespace and display."""
        for _ in range(300):
            if (self.work / "ready").exists():
                return json.loads((self.work / "ready").read_text())
            time.sleep(0.1)
        return self.fail("the session never started")

    def assert_nothing_left(self, ns: str) -> None:
        """Every process of the namespace and pasta are gone, and no X file was left."""
        for _ in range(100):
            if not _in_namespace(ns) and not _running(self.pasta):
                break
            time.sleep(0.1)
        self.assertEqual(_in_namespace(ns), [])
        self.assertEqual(_running(self.pasta), [])
        self.assertEqual(_x_files(), self.x_before)

    def test_sigkill(self) -> None:
        """SIGKILL of browser-fetch takes Xvfb and the browser with it."""
        parent = self.start(60)
        ns = self.ready()["ns"]
        self.assertGreaterEqual(len(_in_namespace(ns)), 3)
        parent.kill()
        parent.wait()
        if parent.stdout is not None:
            parent.stdout.close()
        self.assert_nothing_left(ns)

    def test_sigterm(self) -> None:
        """SIGTERM unwinds browser-fetch, and the namespace goes too."""
        parent = self.start(60)
        ns = self.ready()["ns"]
        parent.send_signal(signal.SIGTERM)
        self.assertEqual(parent.wait(timeout=20), 143)
        if parent.stdout is not None:
            parent.stdout.close()
        self.assert_nothing_left(ns)

    def test_deadline(self) -> None:
        """A session past its deadline fails the fallback and leaves nothing."""
        parent = self.start(4)
        ns = self.ready()["ns"]
        out, _ = parent.communicate(timeout=30)
        self.assertEqual(parent.returncode, 5)
        self.assertIn("longer than", out)
        self.assert_nothing_left(ns)


# A session with two hosts of its own: a.test and b.test resolve to the
# namespace's loopback (network.dns.localDomains), where this serves both on
# GUARD_PORT once the session's network is up. Their requests go to hits.json.
GUARD_SESSION = """\
import http.server, json, sys, threading
sys.path.insert(0, {root!r})
from pathlib import Path
from browser_fetch import session
PORT = {port}
FILLER = "<p>" + "Plain readable paragraph text for the settle check. " * 8 + "</p>"
hits = []

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        hits.append(self.headers.get("Host", "") + self.path)
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", f"http://b.test:{{PORT}}/landing")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = f"<!DOCTYPE html><title>{{self.path}}</title>{{FILLER}}".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        return

start_xvfb = session.start_xvfb

def serve_then_start_xvfb(until):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return start_xvfb(until)

session.start_xvfb = serve_then_start_xvfb
request = json.loads(Path(sys.argv[1]).read_text())
status = session.main(sys.argv[1:])
Path(request["workdir"], "hits.json").write_text(json.dumps(hits))
sys.exit(status)
"""
GUARD_PORT = 8765


class GuardTest(unittest.TestCase):
    """Real Camoufox through Playwright: the fingerprint, and the guard on the first hop."""

    @classmethod
    def setUpClass(cls) -> None:
        """Skip, saying why, where the host cannot make the session's namespace."""
        require_namespaces()

    def setUp(self) -> None:
        """A state and work directory, the stand-in pasta and the two-host session."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.state = self.tmp / "state"
        self.work = self.tmp / "work"
        self.work.mkdir()
        session = self.tmp / "session"
        session.write_text(
            f"#!{sys.executable} -I\n" + GUARD_SESSION.format(root=ROOT, port=GUARD_PORT)
        )
        session.chmod(0o700)
        self.camoufox = browser.Camoufox(
            tools_with(write_fake_pasta(self.tmp), str(session)),
            self.state,
            self.work,
            environ={},
        )

    def test_first_hop_redirect_is_cancelled_without_a_delay(self) -> None:
        """A cross-host 302 on the very first navigation never reaches the other host.

        No delay comes before the navigation. The fingerprint is drawn by
        Camoufox's launcher and its browser, which is also what checks
        Playwright against this Camoufox build.
        """
        identity = self.camoufox.identity(time.monotonic() + 120)
        if identity is None:
            self.fail("no fingerprint was drawn")
        self.assertIn("Firefox/", identity.user_agent)
        fingerprint_path = self.state / browser.FINGERPRINT
        fingerprint = json.loads(fingerprint_path.read_text())
        fingerprint["prefs"]["network.dns.localDomains"] = "a.test,b.test"
        fingerprint_path.write_text(json.dumps(fingerprint))
        # Camoufox installs the guard later on a profile that exists already,
        # so the second launch is the one that raced the first navigation.
        for launch in ("new profile", "existing profile"):
            with self.subTest(launch=launch):
                rendered = self.camoufox.render(
                    f"http://a.test:{GUARD_PORT}/redirect", jar.Jar(), time.monotonic() + 120
                )
                hits = json.loads((self.work / "hits.json").read_text())
                self.assertEqual(hits, [f"a.test:{GUARD_PORT}/redirect"])
                self.assertEqual(
                    rendered.blocked,
                    browser.Blocked(
                        f"http://a.test:{GUARD_PORT}/redirect",
                        f"http://b.test:{GUARD_PORT}/landing",
                        302,
                    ),
                )


# A session whose a.test serves the pages of CookieRoundTripTest on the
# namespace's loopback, recording the Cookie header of each request to
# hits.json and setting each page's cookies.
COOKIE_SESSION = """\
import http.server, json, sys, threading
sys.path.insert(0, {root!r})
from pathlib import Path
from browser_fetch import session
PORT = {port}
SETS = {sets!r}
FILLER = "<p>" + "Plain readable paragraph text for the settle check. " * 8 + "</p>"
hits = []

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        hits.append({{"path": self.path, "cookie": self.headers.get("Cookie", "")}})
        body = f"<!DOCTYPE html><title>{{self.path}}</title>{{FILLER}}".encode()
        self.send_response(200)
        for line in SETS.get(self.path, []):
            self.send_header("Set-Cookie", line)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        return

start_xvfb = session.start_xvfb

def serve_then_start_xvfb(until):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return start_xvfb(until)

session.start_xvfb = serve_then_start_xvfb
request = json.loads(Path(sys.argv[1]).read_text())
status = session.main(sys.argv[1:])
Path(request["workdir"], "hits.json").write_text(json.dumps(hits))
sys.exit(status)
"""
COOKIE_PORT = 8766
FIRST = f"http://a.test:{COOKIE_PORT}/first"
SECOND = f"http://a.test:{COOKIE_PORT}/second"
# What the browser's responses set: one cookie of each kind a row records.
BROWSER_SETS = {
    "/first": [
        "earned=browser; Max-Age=3600; Path=/",
        "fleeting=1; Path=/",
        "dom=1; Domain=a.test; Path=/; Max-Age=3600",
        "lax=1; SameSite=Lax; HttpOnly; Max-Age=3600; Path=/p",
        "strict=1; SameSite=Strict; Max-Age=3600; Path=/",
        "flag; Max-Age=3600; Path=/",
    ],
    "/second": ["late=browser; Max-Age=3600; Path=/"],
}
# The row columns that do not depend on when the cookie was set.
TIMELESS = (
    "originAttributes",
    "name",
    "value",
    "host",
    "path",
    "isSecure",
    "isHttpOnly",
    "inBrowserElement",
    "sameSite",
    "schemeMap",
    "isPartitionedAttributeSet",
)


class CookieRoundTripTest(unittest.TestCase):
    """Real Camoufox and the jar: Gecko's own rows, curl's writes in the browser, and back.

    network.cookie.db.flushIntervalMs is an hour, so a cookie the browser
    sets reaches the database only when the browser closes.
    """

    @classmethod
    def setUpClass(cls) -> None:
        """Skip, saying why, where the host cannot make the session's namespace."""
        require_namespaces()

    def setUp(self) -> None:
        """A state and work directory, the stand-in pasta and the cookie-serving session."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.state = self.tmp / "state"
        self.work = self.tmp / "work"
        self.work.mkdir()
        session = self.tmp / "session"
        session.write_text(
            f"#!{sys.executable} -I\n"
            + COOKIE_SESSION.format(root=ROOT, port=COOKIE_PORT, sets=BROWSER_SETS)
        )
        session.chmod(0o700)
        self.camoufox = browser.Camoufox(
            tools_with(write_fake_pasta(self.tmp), str(session)),
            self.state,
            self.work,
            environ={},
        )
        self.database = self.state / browser.PROFILE / jar.DB_NAME

    def render(self, url: str, cookies: jar.Jar) -> str:
        """Render url and return the Cookie header its page request carried."""
        self.camoufox.render(url, cookies, time.monotonic() + 120)
        hits = json.loads((self.work / "hits.json").read_text())
        (sent,) = [hit["cookie"] for hit in hits if hit["path"] == urlsplit(url).path]
        return sent

    def rows(self) -> dict[str, dict[str, Any]]:
        """The database's rows by name."""
        db = sqlite3.connect(self.database)
        db.row_factory = sqlite3.Row
        try:
            return {row["name"]: dict(row) for row in db.execute("select * from moz_cookies")}
        finally:
            db.close()

    def test_one_jar_for_curl_and_the_browser(self) -> None:
        """Gecko's rows match the jar's, curl's cookies reach the page, the page's reach curl."""
        if self.camoufox.identity(time.monotonic() + 120) is None:
            self.fail("no fingerprint was drawn")
        fingerprint_path = self.state / browser.FINGERPRINT
        fingerprint = json.loads(fingerprint_path.read_text())
        fingerprint["prefs"]["network.dns.localDomains"] = "a.test"
        fingerprint["prefs"]["network.cookie.db.flushIntervalMs"] = 3_600_000
        fingerprint_path.write_text(json.dumps(fingerprint))

        # The browser creates the database and stores what /first set.
        self.assertEqual(self.render(FIRST, jar.Jar()), "")
        db = sqlite3.connect(self.database)
        try:
            version, page_size, sql = (
                db.execute("pragma user_version").fetchone()[0],
                db.execute("pragma page_size").fetchone()[0],
                db.execute("select sql from sqlite_master where name = 'moz_cookies'").fetchone()[
                    0
                ],
            )
        finally:
            db.close()
        self.assertEqual((version, page_size, sql), (17, jar.PAGE_SIZE, jar.CREATE_TABLE))
        gecko = self.rows()
        now = jar.now_us()
        ours = [jar.parse_set_cookie(line, FIRST, now) for line in BROWSER_SETS["/first"]]
        persistent = {c.name: c for c in ours if c is not None and not c.session}
        self.assertEqual(sorted(gecko), sorted(persistent))
        for name, cookie in persistent.items():
            with self.subTest(name=name):
                row = gecko[name]
                mine = {
                    "originAttributes": cookie.origin_attributes,
                    "name": cookie.name,
                    "value": cookie.value,
                    "host": cookie.host,
                    "path": cookie.path,
                    "isSecure": int(cookie.secure),
                    "isHttpOnly": int(cookie.http_only),
                    "inBrowserElement": 0,
                    "sameSite": cookie.same_site,
                    "schemeMap": cookie.scheme_map,
                    "isPartitionedAttributeSet": int(bool(cookie.partition)),
                }
                self.assertEqual({k: row[k] for k in TIMELESS}, mine)
                self.assertEqual(row["expiry"] - row["creationTime"] // 1000, 3_600_000)
                self.assertEqual(row["updateTime"], row["creationTime"])
                self.assertLessEqual(row["lastAccessed"], row["creationTime"])

        # curl replaces one, deletes one, adds one of each lifetime; the page sees exactly that.
        cookies = jar.Jar.of(jar.read(self.database))
        cookies.receive(
            SECOND,
            [
                "earned=curl; Max-Age=3600; Path=/",
                "dom=; Domain=a.test; Path=/; Max-Age=0",
                "persisted=curl; Max-Age=3600; Path=/",
                "sess=curl; Path=/",
            ],
            jar.now_us(),
            None,
        )
        sent = self.render(SECOND, cookies)
        self.assertEqual(
            sorted(sent.split("; ")),
            ["earned=curl", "flag=", "persisted=curl", "sess=curl", "strict=1"],
        )
        self.assertEqual(self.rows()["earned"]["creationTime"], gecko["earned"]["creationTime"])

        # The next curl fetch sends what the browser set at the end of its render.
        fake, holder = fake_curl()
        self.addCleanup(holder.cleanup)
        fake.serve({"https://a.test/": {"status": 200, "headers": {"Content-Type": "text/plain"}}})
        settings = fetch.Settings(
            curl=fake.path,
            browser=self.camoufox,
            workdir=self.work,
            save_dir=self.tmp / "saved",
            browser_mode="never",
            resolve=public,
        )
        fetch.fetch("https://a.test/", settings)
        config = fake.calls()[0]["config"]
        line = next(x for x in config.splitlines() if "Cookie: " in x)
        self.assertEqual(
            sorted(line.split("Cookie: ", 1)[1].rstrip('"').split("; ")),
            ["earned=curl", "flag=", "late=browser", "persisted=curl", "strict=1"],
        )
