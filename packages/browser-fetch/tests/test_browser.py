# Copyright (c) 2026 Bad3r
"""The Camoufox fallback outside the browser: identity, lock, cookie handoff and purge, cleanup."""

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

from browser_fetch import browser, curl, tools
from browser_fetch import cookies as jar

from tests.namespaces import ROOT, require_namespaces, tools_with, write_fake_pasta
from tests.test_cookies import LATER, SCHEMA

VERSION = "158.0.1-beta.41"
URL = "https://a.example/"


def gecko_jar(path: Path, rows: list[tuple[str, str, str]]) -> None:
    """Write a Gecko cookies.sqlite holding (name, value, host) rows."""
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute(SCHEMA)
    db.executemany(
        "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
        " creationTime, isSecure) values ('', ?, ?, ?, '/', ?, 1, 1)",
        [(n, v, h, LATER) for n, v, h in rows],
    )
    db.commit()
    db.close()


def values(path: Path) -> dict[str, str]:
    """The jar's cookies by name."""
    db = sqlite3.connect(path)
    try:
        return dict(db.execute("select name, value from moz_cookies").fetchall())
    finally:
        db.close()


def lw(name: str, value: str) -> jar.Cookie:
    """A LibreWolf cookie of the test host."""
    return jar.Cookie(name, value, ".a.example", "/", LATER, secure=True, created=1)


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
                self.camoufox().render(URL, [], [], time.monotonic() + 0.5)
            session.assert_not_called()
            self.assertLess(time.monotonic() - started, 5)
        finally:
            os.close(holder)

    def run_render(self, librewolf: list[jar.Cookie], received: list[jar.Cookie]) -> dict[str, Any]:
        """Render with a session that acts as the browser would on the profile's jar.

        It stores what it was handed, then the site rotates one cookie and sets a new one.
        """
        database = self.state / browser.PROFILE / jar.DB_NAME
        seen: dict[str, Any] = {}

        def session(
            _self: browser.Camoufox, _mode: str, request: dict[str, Any], _until: float
        ) -> dict[str, Any]:
            seen["before"] = values(database)
            seen["handed"] = {c["name"]: c["value"] for c in request["cookies"]}
            db = sqlite3.connect(database)
            db.executemany(
                "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
                " creationTime, isSecure) values ('', ?, ?, ?, ?, ?, 1, 1)",
                [
                    (c["name"], c["value"], c["domain"], c["path"], LATER)
                    for c in request["cookies"]
                ],
            )
            db.execute("update moz_cookies set value = 'site-rotated' where name = 'rotated'")
            db.execute(
                "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
                " creationTime, isSecure)"
                " values ('', 'new', 'site-set', '.a.example', '/', ?, 1, 1)",
                (LATER,),
            )
            db.commit()
            db.close()
            (self.work / "page.html").write_text("<p>ok</p>")
            return {"url": URL, "status": 200, "contentType": "text/html", "html": True}

        with unittest.mock.patch.object(browser.Camoufox, "_session", autospec=True) as patched:
            patched.side_effect = session
            self.camoufox().render(URL, librewolf, received, time.monotonic() + 30)
        seen["after"] = values(database)
        return seen

    def test_handoff_precedence_and_purge(self) -> None:
        """The browser's own cookie wins; injected values leave after the session, site-set stay."""
        gecko_jar(
            self.state / browser.PROFILE / jar.DB_NAME, [("cf_clearance", "earned", ".a.example")]
        )
        seen = self.run_render(
            [lw("cf_clearance", "librewolf"), lw("sid", "secret"), lw("rotated", "old")],
            [jar.Cookie("__cf_bm", "bm", ".a.example", "/", LATER, secure=True, created=2)],
        )
        self.assertEqual(seen["handed"], {"sid": "secret", "rotated": "old", "__cf_bm": "bm"})
        self.assertEqual(
            seen["after"],
            {"cf_clearance": "earned", "rotated": "site-rotated", "new": "site-set"},
        )
        self.assertFalse((self.state / browser.JOURNAL).exists())

    def test_expired_own_cookie_does_not_keep_librewolfs_out(self) -> None:
        """An expired row in the browser's jar holds no key against LibreWolf's live cookie."""
        expired = jar.Cookie("sid", "old", ".a.example", "/", 1, secure=True, created=1)
        handed = browser.injection([expired], [lw("sid", "fresh")], [], URL, jar.now_ms())
        self.assertEqual([(c.name, c.value) for c in handed], [("sid", "fresh")])

    def test_site_deletion_reaches_the_browsers_own_jar(self) -> None:
        """A cookie the site deleted on curl's hop leaves the profile and is not lent back."""
        gecko_jar(
            self.state / browser.PROFILE / jar.DB_NAME,
            [("sid", "earned", ".a.example"), ("keep", "k", ".a.example")],
        )
        tombstone = jar.Cookie("sid", "", ".a.example", "/", 0, secure=True, created=3)
        seen = self.run_render([lw("sid", "librewolf")], [tombstone])
        self.assertEqual(seen["before"], {"keep": "k"})
        self.assertNotIn("sid", seen["handed"])

    def test_purge_runs_when_the_session_fails(self) -> None:
        """A failed session still takes the injected values out."""
        database = self.state / browser.PROFILE / jar.DB_NAME
        gecko_jar(database, [])

        def session(
            _self: browser.Camoufox, _mode: str, _request: dict[str, Any], _until: float
        ) -> dict[str, Any]:
            db = sqlite3.connect(database)
            db.execute(
                "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
                " creationTime, isSecure) values ('', 'sid', 'secret', '.a.example', '/', ?, 1, 1)",
                (LATER,),
            )
            db.commit()
            db.close()
            msg = "killed"
            raise browser.BrowserError(msg)

        with (
            unittest.mock.patch.object(
                browser.Camoufox, "_session", autospec=True, side_effect=session
            ),
            self.assertRaises(browser.BrowserError),
        ):
            self.camoufox().render(URL, [lw("sid", "secret")], [], time.monotonic() + 30)
        self.assertEqual(values(database), {})

    def test_journal_of_a_killed_run_is_purged_first(self) -> None:
        """Values a SIGKILLed run injected are gone before the next session starts."""
        database = self.state / browser.PROFILE / jar.DB_NAME
        gecko_jar(database, [("sid", "secret", ".a.example"), ("own", "mine", ".a.example")])
        journal = [
            {"name": "sid", "host": ".a.example", "path": "/", "digest": browser.digest("secret")}
        ]
        (self.state / browser.JOURNAL).write_text(json.dumps(journal))
        seen = self.run_render([], [])
        self.assertEqual(seen["before"], {"own": "mine"})

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
            camoufox.render(URL, [], [], time.monotonic() + 60)
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
            camoufox.render(URL, [], [], time.monotonic() + 60)
        self.assertLess(time.monotonic() - started, 10)
        self.assertFalse((self.work / browser.NETWORK_READY).exists())

    def test_expiry_is_clamped_to_geckos_cap(self) -> None:
        """A cookie Gecko would refuse as too long-lived is handed over at the cap."""
        far = jar.Cookie("a", "1", "a.example", "/", 4_000_000_000_000, secure=True, created=1)
        now = 1_800_000_000
        expires = browser.playwright_cookie(far, now=now)["expires"]
        self.assertLessEqual(expires, now + browser.MAXAGE_CAP_SECONDS)
        self.assertGreater(expires, now + browser.MAXAGE_CAP_SECONDS - 86_400)

    def test_playwright_cookie(self) -> None:
        """Gecko's host form, seconds, -1 for a session, and SameSite Gecko accepts."""
        host_only = jar.Cookie(
            "a", "1", "a.example", "/p", 1_710_000_000_000, secure=False, created=1
        )
        session = jar.Cookie(
            "b", "2", ".a.example", "/", jar.SESSION_EXPIRY_MS, secure=True, created=1, session=True
        )
        self.assertEqual(
            browser.playwright_cookie(host_only, now=1_700_000_000),
            {
                "name": "a",
                "value": "1",
                "domain": "a.example",
                "path": "/p",
                "expires": 1_710_000_000,
                "httpOnly": False,
                "secure": False,
                "sameSite": "Lax",
            },
        )
        self.assertEqual(
            (
                browser.playwright_cookie(session)["expires"],
                browser.playwright_cookie(session)["sameSite"],
            ),
            (-1, "None"),
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
                    f"http://a.test:{GUARD_PORT}/redirect", [], [], time.monotonic() + 120
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
