# Copyright (c) 2026 Bad3r
"""Retries, error envelopes, and pagination of the API client."""

import email.message
import http.client
import ssl
import unittest
import unittest.mock
import urllib.error
from typing import TYPE_CHECKING

from warp_devices.api import (
    ATTEMPTS,
    ApiError,
    Client,
    Json,
    Response,
    paginate_cursor,
    paginate_pages,
)

from tests.fixtures import TOKEN, FakeGetter, FakeTransport, envelope, ok

if TYPE_CHECKING:
    from collections.abc import Mapping

GOOD = envelope([{"id": "a"}])


def client(transport: FakeTransport, sleeps: list[float]) -> Client:
    """Return a client that records sleeps instead of sleeping."""
    return Client("acct", TOKEN, transport=transport, sleep=sleeps.append, jitter=lambda: 0.0)


class RetryTest(unittest.TestCase):
    """Transient failures retry; final answers do not."""

    def test_timeout_then_success(self) -> None:
        """A stalled request is retried after a one-second backoff."""
        sleeps: list[float] = []
        transport = FakeTransport(TimeoutError("timed out"), ok(GOOD))
        self.assertEqual(client(transport, sleeps).get("devices", {}), GOOD)
        self.assertEqual(sleeps, [1.0])
        self.assertEqual(len(transport.requests), 2)

    def test_server_error_then_success(self) -> None:
        """A 503 is retried."""
        sleeps: list[float] = []
        transport = FakeTransport(ok({"success": False}, 503), ok(GOOD))
        self.assertEqual(client(transport, sleeps).get("devices", {}), GOOD)

    def test_rate_limit_honors_retry_after(self) -> None:
        """A 429 waits for its Retry-After seconds."""
        sleeps: list[float] = []
        transport = FakeTransport(Response(429, b"{}", "7"), ok(GOOD))
        client(transport, sleeps).get("devices", {})
        self.assertEqual(sleeps, [7.0])

    def test_rate_limit_honors_zero_retry_after(self) -> None:
        """A 429 with Retry-After 0 retries at once instead of backing off."""
        sleeps: list[float] = []
        transport = FakeTransport(Response(429, b"{}", "0"), ok(GOOD))
        client(transport, sleeps).get("devices", {})
        self.assertEqual(sleeps, [0.0])

    def test_cut_off_body_then_success(self) -> None:
        """A 200 whose body is cut off mid-string is retried."""
        sleeps: list[float] = []
        transport = FakeTransport(Response(200, b'{"success": true, "result": [{"na'), ok(GOOD))
        self.assertEqual(client(transport, sleeps).get("devices", {}), GOOD)

    def test_incomplete_read_then_success(self) -> None:
        """A connection that closes early is retried."""
        sleeps: list[float] = []
        transport = FakeTransport(http.client.IncompleteRead(b"{"), ok(GOOD))
        self.assertEqual(client(transport, sleeps).get("devices", {}), GOOD)

    def test_gives_up_after_attempts(self) -> None:
        """Persistent stalls end in one error naming the last reason."""
        sleeps: list[float] = []
        transport = FakeTransport(*[TimeoutError("timed out")] * ATTEMPTS)
        with self.assertRaises(ApiError) as caught:
            client(transport, sleeps).get("devices/registrations", {})
        self.assertIn("devices/registrations", str(caught.exception))
        self.assertIn("TimeoutError", str(caught.exception))
        self.assertEqual(sleeps, [1.0, 2.0, 4.0, 8.0])

    def test_forbidden_is_final(self) -> None:
        """A 403 raises at once with Cloudflare's message and status."""
        sleeps: list[float] = []
        body = {"success": False, "errors": [{"code": 10000, "message": "Authentication error"}]}
        transport = FakeTransport(ok(body, 403))
        with self.assertRaises(ApiError) as caught:
            client(transport, sleeps).get("devices", {})
        self.assertEqual(caught.exception.status, 403)
        self.assertIn("Authentication error", str(caught.exception))
        self.assertEqual(len(transport.requests), 1)

    def test_unsuccessful_envelope_is_final(self) -> None:
        """A 200 with success false is not retried."""
        sleeps: list[float] = []
        transport = FakeTransport(ok({"success": False, "errors": [{"message": "bad window"}]}))
        with self.assertRaisesRegex(ApiError, "bad window"):
            client(transport, sleeps).get("dex/fleet-status/devices", {})
        self.assertEqual(sleeps, [])

    def test_token_stays_out_of_errors(self) -> None:
        """Neither an error nor the client's repr shows the token."""
        sleeps: list[float] = []
        transport = FakeTransport(*[OSError("connection reset")] * ATTEMPTS)
        api = client(transport, sleeps)
        with self.assertRaises(ApiError) as caught:
            api.get("devices", {"per_page": "5"})
        self.assertNotIn(TOKEN, str(caught.exception))
        self.assertNotIn(TOKEN, repr(api))
        url, headers, _ = transport.requests[0]
        self.assertNotIn(TOKEN, url)
        self.assertEqual(headers["Authorization"], f"Bearer {TOKEN}")


class PaginationTest(unittest.TestCase):
    """Both pagination styles collect every page and stop."""

    def test_cursor_pages(self) -> None:
        """A cursor is followed until the last page returns none."""
        pages = {
            "": envelope([{"id": "1"}], cursor="c2"),
            "c2": envelope([{"id": "2"}], cursor=""),
        }
        getter = FakeGetter({"r": lambda params: pages[params.get("cursor", "")]})
        self.assertEqual([item["id"] for item in paginate_cursor(getter, "r")], ["1", "2"])
        self.assertEqual(getter.calls[1][1]["cursor"], "c2")

    def test_repeated_cursor_fails(self) -> None:
        """A cursor that does not advance is an error, not a short listing."""
        getter = FakeGetter({"r": lambda _params: envelope([{"id": "1"}], cursor="same")})
        with self.assertRaisesRegex(ApiError, "stopped advancing"):
            paginate_cursor(getter, "r")
        self.assertEqual(len(getter.calls), 2)

    def test_numbered_pages(self) -> None:
        """Pages are read up to total_pages."""

        def answer(params: Mapping[str, str]) -> Json:
            return envelope([{"id": params["page"]}], total_pages=3)

        getter = FakeGetter({"d": answer})
        self.assertEqual([item["id"] for item in paginate_pages(getter, "d")], ["1", "2", "3"])

    def test_full_page_without_total_pages(self) -> None:
        """A full page with no page count cannot prove the listing complete."""
        full: list[Json] = [{"id": str(n)} for n in range(50)]
        getter = FakeGetter({"d": lambda _params: envelope(full)})
        with self.assertRaisesRegex(ApiError, "without total_pages"):
            paginate_pages(getter, "d")

    def test_short_page_without_total_pages(self) -> None:
        """A short page with no page count is the last one."""
        getter = FakeGetter({"d": lambda _params: envelope([{"id": "1"}])})
        self.assertEqual(len(paginate_pages(getter, "d")), 1)


class EnvelopeShapeTest(unittest.TestCase):
    """A 200 whose envelope is malformed is retried, never read as an empty list."""

    def test_malformed_200_bodies_retry(self) -> None:
        """Missing success, a non-list result, and a missing result each retry once."""
        for body in ({}, {"success": True, "result": "broken"}, {"success": True}):
            with self.subTest(body=body):
                sleeps: list[float] = []
                transport = FakeTransport(ok(body), ok(GOOD))
                self.assertEqual(client(transport, sleeps).get("devices", {}), GOOD)
                self.assertEqual(len(transport.requests), 2)

    def test_malformed_200_gives_up(self) -> None:
        """A body that stays malformed ends in an error, not an empty result."""
        sleeps: list[float] = []
        transport = FakeTransport(*[ok({"success": True})] * ATTEMPTS)
        with self.assertRaisesRegex(ApiError, "malformed body"):
            client(transport, sleeps).get("devices/registrations", {})

    def test_server_error_body_still_retries(self) -> None:
        """A 5xx is retried even when its envelope says success false."""
        sleeps: list[float] = []
        transport = FakeTransport(ok({"success": False, "errors": []}, 502), ok(GOOD))
        self.assertEqual(client(transport, sleeps).get("devices", {}), GOOD)

    def test_success_without_list_off_200_is_final(self) -> None:
        """A non-200 claiming success without a result list is final and keeps its status."""
        cases: tuple[tuple[int, Json], ...] = (
            (201, {"success": True}),
            (404, {"success": True, "result": {}}),
        )
        for status, body in cases:
            with self.subTest(status=status):
                sleeps: list[float] = []
                transport = FakeTransport(ok(body, status), ok(GOOD))
                with self.assertRaisesRegex(ApiError, "without a result list") as caught:
                    client(transport, sleeps).get("devices", {})
                self.assertEqual(caught.exception.status, status)
                self.assertEqual((len(transport.requests), sleeps), (1, []))

    def test_non_json_client_error_is_final(self) -> None:
        """An HTML 404 is final and keeps its status."""
        sleeps: list[float] = []
        transport = FakeTransport(Response(404, b"<html>not found</html>"))
        with self.assertRaises(ApiError) as caught:
            client(transport, sleeps).get("devices", {})
        self.assertEqual(caught.exception.status, 404)
        self.assertEqual(sleeps, [])


class CertificateTest(unittest.TestCase):
    """A failed certificate check is final; retrying cannot change the certificate."""

    def test_certificate_failure_is_final(self) -> None:
        """Wrapped by urllib or bare, it raises after one attempt and names the check."""
        failure = ssl.SSLCertVerificationError(
            1, "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed"
        )
        failure.verify_message = "unable to get local issuer certificate"
        cases: tuple[tuple[str, Exception], ...] = (
            ("urllib", urllib.error.URLError(failure)),
            ("bare", failure),
        )
        for label, raised in cases:
            with self.subTest(label=label):
                sleeps: list[float] = []
                transport = FakeTransport(raised, ok(GOOD))
                with self.assertRaises(ApiError) as caught:
                    client(transport, sleeps).get("devices", {})
                message = str(caught.exception)
                self.assertIn("TLS certificate verification failed", message)
                self.assertIn("unable to get local issuer certificate", message)
                self.assertNotIn(TOKEN, message)
                self.assertEqual((len(transport.requests), sleeps), (1, []))


class TransportTest(unittest.TestCase):
    """The urllib transport keeps a final status and the token out of errors."""

    def test_unreadable_error_body_keeps_status(self) -> None:
        """A 403 whose body read fails stays a final 403."""
        error = urllib.error.HTTPError(
            "https://api.cloudflare.com/x", 403, "Forbidden", email.message.Message(), None
        )
        with (
            unittest.mock.patch.object(error, "read", side_effect=http.client.IncompleteRead(b"{")),
            unittest.mock.patch("urllib.request.urlopen", side_effect=error) as opened,
        ):
            api = Client("acct", TOKEN, sleep=lambda _s: None)
            with self.assertRaises(ApiError) as caught:
                api.get("devices", {})
        self.assertEqual(caught.exception.status, 403)
        self.assertEqual(opened.call_count, 1)

    def test_invalid_header_hides_token(self) -> None:
        """http.client quotes a bad header; the error must not repeat it."""
        secret = "SECRET-TOKEN\nsecond-line"  # noqa: S105 - a fixture value
        api = Client("acct", secret, sleep=lambda _s: None)
        with self.assertRaises(ApiError) as caught:
            api.get("devices", {})
        self.assertNotIn("SECRET-TOKEN", str(caught.exception))
