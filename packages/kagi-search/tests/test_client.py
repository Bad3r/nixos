# Copyright (c) 2026 Bad3r
"""Requests to Kagi and how their answers map to errors."""

import io
import unittest
import urllib.error
import urllib.parse
import urllib.request
from email.message import Message
from typing import cast, override

from kagi_search import client

from tests.test_page import NO_RESULTS, RESULTS

HTTP_OK = 200


def headers(**values: str) -> Message:
    """Return a header block holding the given values."""
    message = Message()
    for name, value in values.items():
        message[name] = value
    return message


class FakeDirector(urllib.request.OpenerDirector):
    """Answer every request with one status and record the requests."""

    def __init__(self, status: int, body: str = "", location: str = "") -> None:
        """Keep the answer to give: a status, a body, and a Location header."""
        super().__init__()
        self.status = status
        self.body = body
        self.location = location
        self.requests: list[urllib.request.Request] = []

    @override
    def open(  # pyright: ignore[reportIncompatibleMethodOverride]
        self, fullurl: urllib.request.Request, data: None = None, timeout: float | None = None
    ) -> io.BytesIO:
        """Record the request and answer it, raising HTTPError for any status but 200."""
        self.requests.append(fullurl)
        if self.status != HTTP_OK:
            raise urllib.error.HTTPError(
                fullurl.full_url, self.status, "", headers(Location=self.location), None
            )
        return io.BytesIO(self.body.encode())


class SearchTest(unittest.TestCase):
    """The request Kagi receives and how its answers map to hits or errors."""

    def test_the_request_carries_the_session_and_narrowed_query(self) -> None:
        """The request sends the cookie, a Safari user agent, and the site: query."""
        director = FakeDirector(200, RESULTS)
        hits = client.search("nix flakes", "tok", allowed=["wiki.nixos.org"], director=director)
        self.assertEqual([h.url for h in hits], ["https://wiki.nixos.org/wiki/Flakes"])
        (request,) = director.requests
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(request.full_url).query)
        self.assertEqual(query, {"q": ["nix flakes site:wiki.nixos.org"]})
        self.assertEqual(request.get_header("Cookie"), "kagi_session=tok")
        self.assertIn("Safari/605.1.15", request.get_header("User-agent") or "")

    def test_limit(self) -> None:
        """At most limit hits come back."""
        hits = client.search("nix", "tok", limit=1, director=FakeDirector(200, RESULTS))
        self.assertEqual([h.title for h in hits], ["NixOS & Nix"])

    def test_no_results_is_an_empty_list(self) -> None:
        """Kagi's no-results answer is no hits, not an error."""
        self.assertEqual(client.search("x", "tok", director=FakeDirector(200, NO_RESULTS)), [])

    def test_a_signin_redirect_means_signed_out(self) -> None:
        """A redirect to the sign-in page is SignedOutError."""
        director = FakeDirector(302, location="https://kagi.com/signin?p=invalid_token")
        with self.assertRaises(client.SignedOutError):
            client.search("x", "tok", director=director)

    def test_a_turnstile_redirect_is_a_challenge(self) -> None:
        """A redirect to the turnstile is ChallengeError."""
        director = FakeDirector(302, location="/turnstile?r=/html/search")
        with self.assertRaises(client.ChallengeError):
            client.search("x", "tok", director=director)

    def test_other_statuses_fail_with_the_code(self) -> None:
        """Any other status fails naming the code."""
        with self.assertRaisesRegex(client.SearchError, "HTTP 503"):
            client.search("x", "tok", director=FakeDirector(503))

    def test_redirects_are_never_followed(self) -> None:
        """The opener's only redirect handler is the refusing one."""
        handlers = cast("list[urllib.request.BaseHandler]", vars(client.opener())["handlers"])
        redirect = [h for h in handlers if isinstance(h, urllib.request.HTTPRedirectHandler)]
        self.assertTrue(redirect)
        self.assertTrue(all(isinstance(h, client.NoRedirect) for h in redirect))
