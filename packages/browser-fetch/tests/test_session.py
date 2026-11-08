# Copyright (c) 2026 Bad3r
"""The session's redirect guard policy and the browser's environment."""

import base64
import json
import os
import re
import socket
import subprocess
import tempfile
import time
import unittest
import unittest.mock
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any

from browser_fetch import session, tools

from tests.namespaces import require_namespaces, run_in_namespace

if TYPE_CHECKING:
    from collections.abc import Callable

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


class CanonicalTargetTest(unittest.TestCase):
    """The browser's spelling of the target is the target."""

    def test_browser_spellings_of_the_target_start(self) -> None:
        """An empty path, a fragment, a default port, case and a Unicode path all match."""
        for target, sent in (
            ("https://a.example", "https://a.example/"),
            ("https://a.example/page#section", "https://a.example/page"),
            ("https://a.example:443/x", "https://a.example/x"),
            ("https://A.Example/x", "https://a.example/x"),
            ("https://a.example/caf\u00e9?q=\u00fc", "https://a.example/caf%C3%A9?q=%C3%BC"),
            ("https://b\u00fccher.example/", "https://xn--bcher-kva.example/"),
        ):
            with self.subTest(target=target):
                policy = session.Policy(target=target, token="t")  # noqa: S106
                self.assertTrue(policy.check("navigate", "", sent, 0))
                self.assertIsNone(policy.blocked)

    def test_other_urls_still_do_not_start(self) -> None:
        """Another path or port on the same host is not the target."""
        for sent in ("https://a.example/other", "https://a.example:8443/", "http://a.example/"):
            with self.subTest(sent=sent):
                policy = session.Policy(target="https://a.example", token="t")  # noqa: S106
                self.assertFalse(policy.check("navigate", "", sent, 0))

    def test_ready_is_a_signal_not_a_navigation(self) -> None:
        """The guard's ready message sets the event and approves nothing."""
        policy = session.Policy(target=TARGET, token="t")  # noqa: S106
        self.assertTrue(policy.check("ready", "", "", 0))
        self.assertTrue(policy.ready.is_set())
        self.assertEqual(policy.approved, set())


class FakeRequest:
    """A Playwright request of the main document."""

    def __init__(self, url: str, before: FakeRequest | None = None, status: int = 200) -> None:
        """A request for url, redirected from before."""
        self.url = url
        self.redirected_from = before
        self.status = status

    def response(self) -> FakeResponse:
        """The response this request got."""
        return FakeResponse(self)

    def is_navigation_request(self) -> bool:
        """Every fake request is one."""
        return True


class FakeResponse:
    """The response to a FakeRequest."""

    def __init__(self, request: FakeRequest) -> None:
        """The response of request."""
        self.request = request
        self.status = request.status
        self.headers = {"content-type": "text/html"}
        self.frame = MAIN


MAIN = object()


class FakePage:
    """A page whose navigations follow a script: the requests a goto makes, or an error."""

    def __init__(
        self,
        hops: list[FakeRequest],
        error: Exception | None = None,
        then: Callable[[], object] | None = None,
        status: int = 0,
    ) -> None:
        """Navigate through hops on goto, then call then, or raise error before any commit.

        status is the navigation timing's responseStatus of the document.
        """
        self.hops = hops
        self.error = error
        self.then = then
        self.status = status
        self.url = "about:blank"
        self.main_frame = MAIN
        self.calls: list[str] = []
        self.listener: Any = None

    def on(self, _event: str, listener: Any) -> None:  # noqa: ANN401
        """Keep the response listener."""
        self.listener = listener

    def goto(self, url: str, **_options: Any) -> None:  # noqa: ANN401
        """Run the scripted navigation."""
        self.calls.append(url)
        if self.error is not None:
            raise self.error
        for hop in self.hops:
            self.listener(FakeResponse(hop))
        if self.hops:
            self.url = self.hops[-1].url
        if self.then is not None:
            self.then()

    def evaluate(self, script: str, *_args: Any) -> Any:  # noqa: ANN401
        """A settled page, or its source."""
        if "outerHTML" in script and "ready" not in script:
            return "<html><body><p>page</p></body></html>"
        return {
            "ready": "complete",
            "size": 10,
            "text": 500,
            "challenge": False,
            "status": self.status,
            "type": "text/html",
        }


class FakeContext:
    """A browser context with one page."""

    def __init__(self, page: FakePage) -> None:
        """The context of page."""
        self.pages = [page]
        self.cookies: list[Any] = []

    def add_cookies(self, cookies: list[Any]) -> None:
        """Record the cookies."""
        self.cookies += cookies


class DriveTest(unittest.TestCase):
    """_drive's order and its result, with the browser scripted."""

    def setUp(self) -> None:
        """A policy for TARGET and a work directory; no settle waits."""
        self.policy = session.Policy(target=TARGET, token="t")  # noqa: S106
        self.work = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        self.addCleanup(__import__("shutil").rmtree, self.work)
        for name, value in (("POLL_SECONDS", 0), ("GUARD_SECONDS", 0.2)):
            patch = unittest.mock.patch.object(session, name, value)
            patch.start()
            self.addCleanup(patch.stop)

    def drive(self, page: FakePage) -> dict[str, Any]:
        """Run _drive on page with one cookie."""
        request = {"workdir": str(self.work), "cookies": [{"name": "a", "value": "1"}]}
        return session.drive(
            FakeContext(page),  # type: ignore[arg-type]
            request,
            self.policy,
            [],
            time.monotonic() + 5,
        )

    def test_no_navigation_before_the_guard_is_ready(self) -> None:
        """Without the guard's ready, nothing is navigated and the session fails."""
        page = FakePage([FakeRequest(TARGET)])
        with self.assertRaisesRegex(session.SessionError, "guard did not start"):
            self.drive(page)
        self.assertEqual(page.calls, [])

    def test_navigation_after_ready(self) -> None:
        """Once ready, the target loads and its page is the result."""
        self.policy.ready.set()
        result = self.drive(FakePage([FakeRequest(TARGET)]))
        self.assertEqual((result["url"], result["status"], result["cookies"]), (TARGET, 200, 1))

    def test_unguarded_cross_host_redirect_is_blocked_afterwards(self) -> None:
        """A hop the guard never saw is still refused from the redirect chain."""
        self.policy.ready.set()
        first = FakeRequest(TARGET, status=302)
        result = self.drive(FakePage([first, FakeRequest("https://b.example/landing", first)]))
        self.assertEqual(
            result["blocked"],
            {"origin": TARGET, "target": "https://b.example/landing", "status": 302},
        )

    def test_script_navigation_blocked_during_goto_has_the_documents_status(self) -> None:
        """A page's own cross-host navigation, refused before goto returns, reports its status.

        The hop has no HTTP status of its own; the redirect is reported with
        the status of the document that started it, or 200 when the browser
        records none, as for a hop refused after the load.
        """
        leave = "https://b.example/next"
        for document, reported in ((404, 404), (0, 200)):
            with self.subTest(document=document):
                self.policy = session.Policy(target=TARGET, token="t")  # noqa: S106
                self.policy.ready.set()
                page = FakePage(
                    [FakeRequest(TARGET, status=document or 200)],
                    then=lambda: self.policy.check("navigate", TARGET, leave, 0),
                    status=document,
                )
                result = self.drive(page)
                self.assertEqual(
                    result["blocked"], {"origin": TARGET, "target": leave, "status": reported}
                )

    def test_navigation_that_never_commits_is_a_failure(self) -> None:
        """A goto timeout on about:blank is an error, never an empty 200 page."""
        self.policy.ready.set()
        page = FakePage([], error=TimeoutError("Timeout 60000ms exceeded."))
        with self.assertRaisesRegex(session.SessionError, "no document.*Timeout 60000ms"):
            self.drive(page)
        self.assertFalse((self.work / "page.html").exists())


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


class ProxyTest(unittest.TestCase):
    """The browser leaves through the proxy curl uses for the page (curl's lib/proxy.c)."""

    def test_curls_variables_in_curls_order(self) -> None:
        """https_proxy, HTTPS_PROXY, all_proxy, then ALL_PROXY; an empty one counts as unset."""
        a, b, c, d = (f"http://{name}.example:3128" for name in "abcd")
        for environ, server in (
            ({"ALL_PROXY": d}, d),
            ({"all_proxy": c, "ALL_PROXY": d}, c),
            ({"HTTPS_PROXY": b, "all_proxy": c, "ALL_PROXY": d}, b),
            ({"https_proxy": a, "HTTPS_PROXY": b, "all_proxy": c}, a),
            ({"https_proxy": "", "HTTPS_PROXY": "", "ALL_PROXY": d}, d),
            ({"http_proxy": a, "HTTP_PROXY": b}, None),
        ):
            with self.subTest(environ=environ):
                settings = session.proxy_settings(TARGET, environ)
                self.assertEqual(settings and settings["server"], server)

    def test_no_proxy_is_curls_and_never_handed_over(self) -> None:
        """The browser gets curl's proxy for the page, or none when curl goes direct; no bypass.

        Each case is one where Juggler's bypass test, the host's endsWith(entry),
        and curl's match_host disagree; NO_PROXY_CASES in test_curl holds curl's.
        """
        proxy = "http://proxy.example:3128"
        for page, no_proxy, server in (
            ("https://notexample.com/", "example.com", proxy),
            ("https://example.com/", ".example.com", None),
            ("https://example.com/", "*", None),
            ("https://example.com/", "other.example,", proxy),
            ("https://example.com/", "EXAMPLE.com", None),
            ("https://192.0.2.7/", "192.0.2.0/24", None),
        ):
            with self.subTest(page=page, no_proxy=no_proxy):
                settings = session.proxy_settings(page, {"ALL_PROXY": proxy, "no_proxy": no_proxy})
                self.assertEqual(settings, None if server is None else {"server": server})

    def test_schemes_firefox_takes(self) -> None:
        """Each of curl's proxy schemes as Firefox's, with curl's port when the URL has none.

        curl (lib/peer.c): no scheme is http, socks is SOCKS4, socks4a and
        socks5h are SOCKS4 and SOCKS5, and the port defaults to the scheme's
        defport (lib/protocol.c): 80 for http, 443 for https, 1080 for SOCKS.
        Playwright's Firefox takes http, https, socks4 and socks5, and reads
        an empty SOCKS port as NaN (ffBrowser.ts, toJugglerProxyOptions).
        """
        for given, server in (
            ("proxy.example:3128", "http://proxy.example:3128"),
            ("proxy.example", "http://proxy.example:80"),
            ("http://proxy.example", "http://proxy.example:80"),
            ("http://proxy.example:3128/path", "http://proxy.example:3128"),
            ("https://proxy.example", "https://proxy.example:443"),
            ("socks5h://proxy.example:1080", "socks5://proxy.example:1080"),
            ("SOCKS4A://proxy.example:1080", "socks4://proxy.example:1080"),
            ("socks5://proxy.example:1080", "socks5://proxy.example:1080"),
            ("socks://proxy.example:1080", "socks4://proxy.example:1080"),
            ("socks5h://proxy.example", "socks5://proxy.example:1080"),
            ("socks5://proxy.example", "socks5://proxy.example:1080"),
            ("socks4a://proxy.example", "socks4://proxy.example:1080"),
            ("socks4://proxy.example", "socks4://proxy.example:1080"),
            ("socks://proxy.example", "socks4://proxy.example:1080"),
        ):
            with self.subTest(given=given):
                self.assertEqual(
                    session.proxy_settings(TARGET, {"ALL_PROXY": given, "no_proxy": "b.example"}),
                    {"server": server},
                )

    def test_credentials_go_decoded(self) -> None:
        """An HTTP proxy's credentials go to Playwright's own fields, decoded as curl decodes them.

        curl's parse_proxy reads the URL's user and password decoded
        (CURLU_URLDECODE); Playwright keeps only the scheme and host of
        `server` (browserContext.ts, normalizeProxySettings).
        """
        for given, settings in (
            (
                "http://al%40ice:p%3Ass@proxy.example:3128",
                {"server": "http://proxy.example:3128", "username": "al@ice", "password": "p:ss"},
            ),
            (
                "https://bob@proxy.example",
                {"server": "https://proxy.example:443", "username": "bob", "password": ""},
            ),
        ):
            with self.subTest(given=given):
                self.assertEqual(session.proxy_settings(TARGET, {"ALL_PROXY": given}), settings)

    def test_socks_credentials_fail(self) -> None:
        """Playwright's Firefox cannot authenticate to SOCKS, so the browser fails, never goes bare.

        normalizeProxySettings throws for socks4 or socks5 with a username or
        password; curl authenticates (lib/socks.c).
        """
        for given in ("socks5h://alice:pw@proxy.example:1080", "socks4://alice@proxy.example"):
            with self.subTest(given=given), self.assertRaisesRegex(session.SessionError, "SOCKS"):
                session.proxy_settings(TARGET, {"ALL_PROXY": given})

    def test_a_proxy_firefox_cannot_reach_as_curl_does_fails(self) -> None:
        """An IPv6 proxy address, or a scheme curl refuses, fails the browser rather than diverge.

        Playwright hands Juggler the URL's hostname, which keeps an IPv6
        address in brackets; Gecko takes that for a name it cannot resolve.
        """
        for given, error in (
            ("socks5h://[2001:db8::1]:1080", "IPv6"),
            ("http://[2001:db8::1]:3128", "IPv6"),
            ("ftp://proxy.example:21", "ftp://"),
            ("http://proxy.example:99999", "port"),
        ):
            with self.subTest(given=given), self.assertRaisesRegex(session.SessionError, error):
                session.proxy_settings(TARGET, {"ALL_PROXY": given})
        direct = {"ALL_PROXY": "socks5h://[2001:db8::1]:1080", "no_proxy": "a.example"}
        self.assertIsNone(session.proxy_settings(TARGET, direct))

    def test_a_twin_curl_routes_otherwise_is_not_followed(self) -> None:
        """A redirect to the www. twin curl would reach through another proxy is reported instead.

        no_proxy=www.a.example names the twin alone (match_host: the entry is
        longer than a.example), so curl proxies a.example and goes direct to
        www.a.example, while the browser has one proxy for the fetch.
        """
        twin = "https://www.a.example/next"
        proxy = {"ALL_PROXY": "http://proxy.example:3128"}
        twin_direct = {**proxy, "no_proxy": "www.a.example"}
        split = session.Policy(target=TARGET, token="t", environ=twin_direct)  # noqa: S106
        self.assertFalse(split.check("redirect", TARGET, twin, 302))
        self.assertEqual(split.blocked, {"origin": TARGET, "target": twin, "status": 302})
        self.assertFalse(split.check("navigate", TARGET, twin, 0))
        alike = session.Policy(target=TARGET, token="t", environ=proxy)  # noqa: S106
        self.assertTrue(alike.check("redirect", TARGET, twin, 302))


@unittest.skipIf(
    tools.CURL.startswith("@"), "the source tree's tools are not store paths; run the package"
)
class CurlProxyTest(unittest.TestCase):
    """curl-impersonate itself, on loopback, against the proxy the browser is given."""

    def curl(self, proxy: str) -> subprocess.Popen[str]:
        """Start curl on TARGET through proxy; a.example resolves to a documentation address."""
        return subprocess.Popen(
            [
                tools.CURL,
                "--disable",
                "--silent",
                "--verbose",
                "--max-time",
                "5",
                "--resolve",
                "a.example:443:192.0.2.1",
                TARGET,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            env={"PATH": "/var/empty", "ALL_PROXY": proxy},
        )

    def test_default_port_is_curls(self) -> None:
        """A proxy URL with no port: the browser's port is the one curl connects to."""
        for scheme in ("http", "https", "socks", "socks4", "socks4a", "socks5", "socks5h"):
            with self.subTest(scheme=scheme):
                proxy = f"{scheme}://127.0.0.1"
                _, log = self.curl(proxy).communicate(timeout=30)
                tried = re.search(r"Trying 127\.0\.0\.1:(\d+)", log)
                settings = session.proxy_settings(TARGET, {"ALL_PROXY": proxy}) or {}
                self.assertIsNotNone(tried, log)
                port = settings.get("server", "").rpartition(":")[2]
                self.assertEqual(port, tried and tried[1])

    def test_protocol_is_curls(self) -> None:
        """The browser speaks to the proxy in the protocol curl's first bytes show."""
        for scheme in ("http", "https", "socks", "socks4", "socks4a", "socks5", "socks5h"):
            with (
                self.subTest(scheme=scheme),
                socket.create_server(("127.0.0.1", 0)) as listener,
            ):
                listener.settimeout(20)
                proxy = f"{scheme}://127.0.0.1:{listener.getsockname()[1]}"
                running = self.curl(proxy)
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(20)
                    first = connection.recv(16)
                running.kill()
                running.communicate()
                spoken = {4: "socks4", 5: "socks5", 0x16: "https"}.get(first[0], "http")
                self.assertEqual(first.startswith(b"CONNECT "), spoken == "http")
                settings = session.proxy_settings(TARGET, {"ALL_PROXY": proxy})
                self.assertEqual(scheme_of(settings), spoken)

    def test_credentials_are_curls(self) -> None:
        """The credentials the browser gets are the ones curl sends the proxy."""
        with socket.create_server(("127.0.0.1", 0)) as listener:
            listener.settimeout(20)
            proxy = f"http://al%40ice:p%3Ass@127.0.0.1:{listener.getsockname()[1]}"
            running = self.curl(proxy)
            connection, _ = listener.accept()
            with connection:
                connection.settimeout(20)
                sent = b""
                while b"\r\n\r\n" not in sent:
                    chunk = connection.recv(4096)
                    if not chunk:
                        break
                    sent += chunk
            running.kill()
            running.communicate()
        found = re.search(rb"\r\nProxy-Authorization: Basic (\S+)\r\n", sent)
        self.assertIsNotNone(found, sent)
        settings = session.proxy_settings(TARGET, {"ALL_PROXY": proxy}) or {}
        self.assertEqual(
            base64.b64decode(found[1] if found else b"").decode(),
            f"{settings.get('username')}:{settings.get('password')}",
        )


def scheme_of(settings: dict[str, str] | None) -> str:
    """The scheme of Playwright's proxy server."""
    return (settings or {}).get("server", "").partition("://")[0]


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
        require_namespaces()

    def test_blocked_ranges_are_prohibited_and_public_ones_are_not(self) -> None:
        """Private addresses fail with EACCES from a rule; a public one only lacks a route here."""
        private = ["10.0.0.1", "100.96.0.9", "169.254.169.254", "172.16.0.1", "192.168.1.1"]
        with tempfile.TemporaryDirectory(prefix="browser-fetch-test-") as work:
            ran = run_in_namespace(
                CONFINED.replace("sys.argv[2:]", repr([*private, "93.184.215.14"])), Path(work)
            )
        self.assertEqual(ran.returncode, 0, ran.stderr)
        out = json.loads(ran.stdout)
        for address in private:
            with self.subTest(address=address):
                self.assertEqual(out[address], "EACCES")
        self.assertEqual(out["93.184.215.14"], "ENETUNREACH")
        self.assertNotEqual(out["rule del"], 0)
