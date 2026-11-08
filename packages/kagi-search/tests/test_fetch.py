# Copyright (c) 2026 Bad3r
"""Which hosts the page fetcher reaches, and what it sends them."""

import http.server
import os
import tempfile
import threading
import time
import unittest
import unittest.mock
from typing import override

from kagi_search import client, fetch, render


class AddressTest(unittest.TestCase):
    """Which URLs the fetcher refuses, and which addresses it connects to."""

    def test_refused_urls(self) -> None:
        """User information, other schemes, and malformed URLs never reach a socket."""
        urls = [
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
                with self.subTest(url=url), self.assertRaises(fetch.InvalidURLError):
                    fetch.fetch_page(url)
            connect.assert_not_called()

    def test_local_and_private_addresses_are_connected_to(self) -> None:
        """Loopback, link-local, private, CGNAT, ULA and embedded-IPv4 hosts reach connect."""
        inet, inet6 = fetch.socket.AF_INET, fetch.socket.AF_INET6
        cases = {
            "http://10.0.0.1/": (inet, ("10.0.0.1", 80)),
            "http://192.168.1.1:8080/admin": (inet, ("192.168.1.1", 8080)),
            "http://172.16.0.1/": (inet, ("172.16.0.1", 80)),
            "http://169.254.169.254/latest/meta-data/": (inet, ("169.254.169.254", 80)),
            "http://100.64.0.1/": (inet, ("100.64.0.1", 80)),
            "http://127.0.0.1:9/": (inet, ("127.0.0.1", 9)),
            "http://2130706433/": (inet, ("127.0.0.1", 80)),
            "http://[::1]:8080/": (inet6, ("::1", 8080)),
            "http://[fd00::1]/": (inet6, ("fd00::1", 80)),
            "http://[fe80::1]/": (inet6, ("fe80::1", 80)),
            "http://[64:ff9b::7f00:1]/": (inet6, ("64:ff9b::7f00:1", 80)),
            "http://[::ffff:10.0.0.1]/": (inet6, ("::ffff:10.0.0.1", 80)),
            "http://[::127.0.0.1]/": (inet6, ("::127.0.0.1", 80)),
        }
        for url, (family, address) in cases.items():
            with (
                self.subTest(url=url),
                unittest.mock.patch.object(fetch, "_DeadlineSocket") as sockets,
            ):
                sockets.return_value.connect.side_effect = ConnectionRefusedError()
                with self.assertRaisesRegex(fetch.FetchError, r"^cannot connect to ") as raised:
                    fetch.fetch_page(url)
                self.assertNotIsInstance(raised.exception, fetch.InvalidURLError)
                sockets.assert_called_once_with(family, fetch.socket.SOCK_STREAM)
                sockets.return_value.connect.assert_called_once_with(address)

    def test_a_single_label_host_is_connected_to(self) -> None:
        """A LAN name without a dot resolves and reaches connect like any other host."""
        lan = [(fetch.socket.AF_INET, fetch.socket.SOCK_STREAM, 6, "", ("192.168.1.20", 80))]
        with (
            unittest.mock.patch.object(fetch.socket, "getaddrinfo", return_value=lan) as lookup,
            unittest.mock.patch.object(fetch, "_DeadlineSocket") as sockets,
            self.assertRaisesRegex(fetch.FetchError, r"^cannot connect to router: "),
        ):
            sockets.return_value.connect.side_effect = ConnectionRefusedError()
            fetch.fetch_page("http://router/")
        self.assertEqual(lookup.call_args.args[:2], ("router", 80))
        sockets.return_value.connect.assert_called_once_with(("192.168.1.20", 80))

    def test_an_address_family_the_host_lacks_falls_through(self) -> None:
        """An IPv6 socket the host refuses moves on to the name's IPv4 address."""
        both = [
            (fetch.socket.AF_INET6, fetch.socket.SOCK_STREAM, 6, "", ("::1", 80, 0, 0)),
            (fetch.socket.AF_INET, fetch.socket.SOCK_STREAM, 6, "", ("127.0.0.1", 80)),
        ]
        ipv4 = unittest.mock.MagicMock()
        ipv4.connect.side_effect = ConnectionRefusedError()
        with (
            unittest.mock.patch.object(fetch.socket, "getaddrinfo", return_value=both),
            unittest.mock.patch.object(
                fetch, "_DeadlineSocket", side_effect=[OSError(97, "no IPv6"), ipv4]
            ),
            self.assertRaisesRegex(fetch.FetchError, r"^cannot connect to localhost: "),
        ):
            fetch.fetch_page("http://localhost/")
        ipv4.connect.assert_called_once_with(("127.0.0.1", 80))


TRICKLE_BYTES = 80
TRICKLE_STEP = 0.05
TEST_DEADLINE_SECONDS = 1
DEADLINE_SLACK_SECONDS = 1


class _Handler(http.server.BaseHTTPRequestHandler):
    """Serve a page and redirects, recording request headers."""

    seen: list[tuple[str, str | None, str | None]] = []  # noqa: RUF012 - shared by test design

    def do_GET(self) -> None:
        """Answer /page with HTML and /fine, /hop, or /ftp with a redirect."""
        type(self).seen.append(
            (self.path, self.headers.get("Cookie"), self.headers.get("User-Agent"))
        )
        host = self.headers.get("Host", "")
        targets = {
            "/hop": f"http://localhost:{host.rsplit(':', 1)[-1]}/page",
            "/ftp": "ftp://example.test/x",
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
    """The fetcher against a server listening on 127.0.0.1."""

    @override
    def setUp(self) -> None:
        _Handler.seen = []
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        environment = unittest.mock.patch.dict(
            os.environ,
            {"XDG_STATE_HOME": f"{state.name}/state", "XDG_CACHE_HOME": f"{state.name}/cache"},
        )
        environment.start()
        self.addCleanup(environment.stop)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.port = server.server_address[1]

    def test_a_loopback_page_is_opened_by_address_and_by_localhost(self) -> None:
        """http://127.0.0.1:<port>/ and http://localhost:<port>/ both return the page."""
        for host in ("127.0.0.1", "localhost"):
            with self.subTest(host=host):
                page = fetch.fetch_page(f"http://{host}:{self.port}/")
                self.assertEqual(page.url, f"http://{host}:{self.port}/")
                self.assertFalse(page.redirected)
                self.assertEqual(render.render(page).lines, ["hello"])
        self.assertEqual([path for path, _, _ in _Handler.seen], ["/", "/"])

    def test_page_is_fetched_without_cookies(self) -> None:
        """A relative redirect is followed, and no request carries a cookie."""
        page = fetch.fetch_page(f"http://127.0.0.1:{self.port}/fine")
        self.assertEqual(page.url, f"http://127.0.0.1:{self.port}/page")
        self.assertTrue(page.redirected)
        self.assertEqual(render.render(page).lines, ["hello"])
        self.assertEqual([path for path, _, _ in _Handler.seen], ["/fine", "/page"])
        for _, cookie_header, agent in _Handler.seen:
            self.assertIsNone(cookie_header)
            self.assertEqual(agent, client.USER_AGENT)

    def test_a_fragment_is_not_a_redirect(self) -> None:
        """A URL with a fragment that answers directly is not a redirect."""
        page = fetch.fetch_page(f"http://127.0.0.1:{self.port}/page#part")
        self.assertFalse(page.redirected)

    def test_a_redirect_to_another_loopback_url_is_followed(self) -> None:
        """A redirect from 127.0.0.1 to a localhost URL is followed to its page."""
        page = fetch.fetch_page(f"http://127.0.0.1:{self.port}/hop")
        self.assertEqual(page.url, f"http://localhost:{self.port}/page")
        self.assertTrue(page.redirected)
        self.assertEqual(render.render(page).lines, ["hello"])
        self.assertEqual([path for path, _, _ in _Handler.seen], ["/hop", "/page"])

    def test_redirect_to_another_scheme_is_refused(self) -> None:
        """A redirect to ftp is refused."""
        with self.assertRaises(fetch.InvalidURLError):
            fetch.fetch_page(f"http://127.0.0.1:{self.port}/ftp")

    def test_a_trickling_page_stops_at_the_deadline(self) -> None:
        """A server sending a byte at a time cannot hold the fetch past its deadline."""
        started = time.monotonic()
        with (
            unittest.mock.patch.object(fetch, "FETCH_DEADLINE_SECONDS", TEST_DEADLINE_SECONDS),
            self.assertRaisesRegex(fetch.FetchError, "took longer than 1 s"),
        ):
            fetch.fetch_page(f"http://127.0.0.1:{self.port}/trickle")
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, TEST_DEADLINE_SECONDS + DEADLINE_SLACK_SECONDS)

    def test_a_non_text_charset_falls_back_to_utf_8(self) -> None:
        """charset=base64 names a codec that cannot decode text; the page decodes as UTF-8."""
        page = fetch.fetch_page(f"http://127.0.0.1:{self.port}/b64")
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
            fetch.fetch_page("http://example.test/")
