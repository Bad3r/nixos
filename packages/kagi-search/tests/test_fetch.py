# Copyright (c) 2026 Bad3r
"""Which hosts the page fetcher may reach, and what it sends them."""

import http.server
import ipaddress
import threading
import time
import unittest
import unittest.mock
from typing import override

from kagi_search import client, fetch, render


class AddressTest(unittest.TestCase):
    """Which hosts the fetcher may reach."""

    def test_public_addresses(self) -> None:
        """Only global unicast addresses pass, embedded IPv4 included."""
        cases = {
            "93.184.216.34": True,
            "2606:4700::1111": True,
            "::ffff:8.8.8.8": True,
            "127.0.0.1": False,
            "10.1.2.3": False,
            "172.16.0.1": False,
            "192.168.1.1": False,
            "169.254.169.254": False,
            "100.96.0.9": False,
            "0.0.0.0": False,  # noqa: S104 - an address under test
            "224.0.0.1": False,
            "255.255.255.255": False,
            "240.0.0.1": False,
            "::1": False,
            "::": False,
            "fe80::1": False,
            "fc00::1": False,
            "ff02::1": False,
            "::ffff:127.0.0.1": False,
            "::127.0.0.1": False,
            "2002:7f00:1::": False,
            "64:ff9b::7f00:1": False,
            "64:ff9b::808:808": True,
        }
        for address, expected in cases.items():
            with self.subTest(address=address):
                self.assertEqual(fetch.is_public_address(ipaddress.ip_address(address)), expected)

    def test_refused_urls(self) -> None:
        """Private hosts, user information, and other schemes never reach a socket."""
        urls = [
            "http://127.0.0.1/",
            "http://[::1]:8080/",
            "http://10.0.0.1/admin",
            "http://169.254.169.254/latest/meta-data/",
            "http://2130706433/",
            "http://user:pw@example.com/",
            "https://example.com@10.0.0.1/",
            "file:///etc/passwd",
            "ftp://example.com/",
            "http://exa mple.com/",
            "http://example.com\\@evil.example/",
            "http://[::1/",
            "http://example.com:99999/",
        ]
        with unittest.mock.patch.object(fetch.socket.socket, "connect") as connect:
            for url in urls:
                with self.subTest(url=url), self.assertRaises(fetch.BlockedURLError):
                    fetch.fetch_page(url)
            connect.assert_not_called()


TRICKLE_BYTES = 80
TRICKLE_STEP = 0.05
TEST_DEADLINE_SECONDS = 1
DEADLINE_SLACK_SECONDS = 1


class _Handler(http.server.BaseHTTPRequestHandler):
    """Serve a page and redirects, recording request headers."""

    seen: list[tuple[str, str | None, str | None]] = []  # noqa: RUF012 - shared by test design

    def do_GET(self) -> None:
        """Answer /page with HTML and /hop or /ftp with a redirect."""
        type(self).seen.append(
            (self.path, self.headers.get("Cookie"), self.headers.get("User-Agent"))
        )
        host = self.headers.get("Host", "")
        targets = {
            "/hop": f"http://private.test:{host.rsplit(':', 1)[-1]}/secret",
            "/ftp": "ftp://public.test/x",
            "/fine": "/page",
        }
        if self.path == "/trickle":
            self.trickle()
            return
        if self.path in targets:
            self.send_response(302)
            self.send_header("Location", targets[self.path])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = b"<title>Local</title><p>hello</p>"
        charset = "base64" if self.path == "/b64" else "utf-8"
        self.send_response(200)
        self.send_header("Content-Type", f"text/html; charset={charset}")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def trickle(self) -> None:
        """Send TRICKLE_BYTES of body one byte per TRICKLE_STEP seconds."""
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(TRICKLE_BYTES))
        self.end_headers()
        try:
            for _ in range(TRICKLE_BYTES):
                self.wfile.write(b"x")
                self.wfile.flush()
                time.sleep(TRICKLE_STEP)
        except OSError:
            return

    @override
    def log_message(self, format: str, *args: object) -> None:
        """Keep the test output quiet."""


class RedirectTest(unittest.TestCase):
    """The fetcher against a loopback server posing as a public host."""

    @override
    def setUp(self) -> None:
        _Handler.seen = []
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.port = server.server_address[1]
        public = fetch.is_public_address

        def resolve(host: str, port: int) -> list[str]:
            del port
            return {"public.test": ["127.0.0.1"], "private.test": ["10.9.8.7"]}[host]

        def allowed(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
            return str(address) == "127.0.0.1" or public(address)

        for patch in (
            unittest.mock.patch.object(fetch, "resolve", resolve),
            unittest.mock.patch.object(fetch, "is_public_address", allowed),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def test_page_is_fetched_without_cookies(self) -> None:
        """A public page arrives, redirects within public hosts are followed."""
        page = fetch.fetch_page(f"http://public.test:{self.port}/fine")
        self.assertEqual(page.url, f"http://public.test:{self.port}/page")
        self.assertTrue(page.redirected)
        self.assertEqual(render.render(page).lines, ["hello"])
        self.assertEqual([path for path, _, _ in _Handler.seen], ["/fine", "/page"])
        for _, cookie_header, agent in _Handler.seen:
            self.assertIsNone(cookie_header)
            self.assertEqual(agent, client.USER_AGENT)

    def test_a_fragment_is_not_a_redirect(self) -> None:
        """A URL with a fragment that answers directly is not a redirect."""
        page = fetch.fetch_page(f"http://public.test:{self.port}/page#part")
        self.assertFalse(page.redirected)

    def test_redirect_to_a_private_host_is_refused(self) -> None:
        """A redirect to a host resolving to 10/8 fails before any connection."""
        with self.assertRaisesRegex(fetch.BlockedURLError, "10.9.8.7"):
            fetch.fetch_page(f"http://public.test:{self.port}/hop")
        self.assertEqual([path for path, _, _ in _Handler.seen], ["/hop"])

    def test_redirect_to_another_scheme_is_refused(self) -> None:
        """A redirect to ftp is refused."""
        with self.assertRaises(fetch.BlockedURLError):
            fetch.fetch_page(f"http://public.test:{self.port}/ftp")

    def test_a_trickling_page_stops_at_the_deadline(self) -> None:
        """A server sending a byte at a time cannot hold the fetch past its deadline."""
        started = time.monotonic()
        with (
            unittest.mock.patch.object(fetch, "FETCH_DEADLINE_SECONDS", TEST_DEADLINE_SECONDS),
            self.assertRaisesRegex(fetch.FetchError, "took longer than 1 s"),
        ):
            fetch.fetch_page(f"http://public.test:{self.port}/trickle")
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, TEST_DEADLINE_SECONDS + DEADLINE_SLACK_SECONDS)

    def test_a_non_text_charset_falls_back_to_utf_8(self) -> None:
        """charset=base64 names a codec that cannot decode text; the page decodes as UTF-8."""
        page = fetch.fetch_page(f"http://public.test:{self.port}/b64")
        self.assertEqual(page.body, "<title>Local</title><p>hello</p>")


class FailureTest(unittest.TestCase):
    """How a failed request is reported."""

    def test_an_error_without_a_message_names_its_type(self) -> None:
        """A connection error with an empty message is reported by its type."""
        with (
            unittest.mock.patch.object(
                fetch.urllib.request.OpenerDirector, "open", side_effect=ConnectionResetError()
            ),
            self.assertRaisesRegex(fetch.FetchError, r"^request failed: ConnectionResetError$"),
        ):
            fetch.fetch_page("http://public.test/")
