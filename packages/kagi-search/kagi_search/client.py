# Copyright (c) 2026 Bad3r
"""Kagi's results page fetched with a session cookie."""

from __future__ import annotations

import urllib.error
import urllib.parse
import urllib.request
from typing import TYPE_CHECKING, override

from kagi_search.page import Hit, filter_hits, kagi_query, parse_page

if TYPE_CHECKING:
    from email.message import Message
    from typing import IO
    from urllib.request import Request

SEARCH_URL = "https://kagi.com/html/search"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/27.2 Safari/605.1.15"
)
TIMEOUT = 20
REDIRECTS = range(300, 400)


class SearchError(Exception):
    """The search did not produce a results page."""


class SignedOutError(SearchError):
    """Kagi sent the request to its sign-in page."""

    def __init__(self) -> None:
        """Tell the user to sign in to Kagi in LibreWolf again."""
        super().__init__(
            "Kagi rejected LibreWolf's session (signed out or expired); "
            "sign in to kagi.com in LibreWolf again"
        )


class ChallengeError(SearchError):
    """Kagi answered with a bot challenge."""

    def __init__(self) -> None:
        """Name the bot challenge as the failure."""
        super().__init__("Kagi answered with a bot challenge instead of results")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse every redirect."""

    @override
    def redirect_request(
        self,
        req: Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: Message,
        newurl: str,
    ) -> None:
        """Return no request, so urllib raises the redirect as an HTTPError."""


def opener() -> urllib.request.OpenerDirector:
    """Return a urllib opener that never follows a redirect."""
    return urllib.request.build_opener(NoRedirect)


def fetch_page(query: str, cookie: str, director: urllib.request.OpenerDirector) -> str:
    """Return the HTML of Kagi's results page for the query."""
    request = urllib.request.Request(  # noqa: S310 - SEARCH_URL is https
        f"{SEARCH_URL}?{urllib.parse.urlencode({'q': query})}",
        headers={
            "Cookie": f"kagi_session={cookie}",
            "User-Agent": USER_AGENT,
            "Accept": "text/html",
        },
    )
    try:
        with director.open(request, timeout=TIMEOUT) as response:
            body: bytes = response.read()
    except urllib.error.HTTPError as error:
        error.close()
        if error.code in REDIRECTS:
            location = error.headers.get("Location", "")
            if "signin" in location or "login" in location:
                raise SignedOutError from None
            if "turnstile" in location:
                raise ChallengeError from None
            msg = f"Kagi redirected to {location or 'an unnamed location'}"
            raise SearchError(msg) from None
        msg = f"Kagi answered HTTP {error.code}"
        raise SearchError(msg) from None
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        reason = error.reason if isinstance(error, urllib.error.URLError) else error
        msg = f"request to Kagi failed: {reason}"
        raise SearchError(msg) from None
    return body.decode("utf-8", errors="replace")


def search(  # noqa: PLR0913 - keyword-only options of the public entry point
    query: str,
    cookie: str,
    *,
    allowed: list[str] | None = None,
    blocked: list[str] | None = None,
    limit: int = 10,
    director: urllib.request.OpenerDirector | None = None,
) -> list[Hit]:
    """Return at most limit hits for the query, filtered by allowed and blocked domains."""
    page = fetch_page(kagi_query(query, allowed), cookie, director or opener())
    return filter_hits(parse_page(page), allowed, blocked)[:limit]
