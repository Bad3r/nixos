# Copyright (c) 2026 Bad3r
"""Kagi's results page, requested through browser-fetch with the jar's Kagi session."""

from __future__ import annotations

from typing import TYPE_CHECKING
from urllib.parse import urlencode

from browser_fetch import curl, fetch

from kagi_search.page import Hit, filter_hits, kagi_query, parse_page

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Sequence

SEARCH_URL = "https://kagi.com/html/search"
SESSION_COOKIE = "kagi_session"
SIGN_IN = "run `browser-fetch login https://kagi.com` and sign in"
# The User-Agent kagi_search.fetch opens pages with; Kagi's search sends the fingerprint's.
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/27.2 Safari/605.1.15"
)
# Within the plugin's 60 s timeout for the whole command.
DEADLINE_SECONDS = 45
_REDIRECTS = range(300, 400)
_OK = 200


class SearchError(Exception):
    """The search did not produce a results page."""


class SessionError(Exception):
    """browser-fetch's cookie jar holds no Kagi session."""

    def __init__(self, warnings: Sequence[str] = ()) -> None:
        """Tell the user to sign in, after anything that kept the jar from being read."""
        why = f" ({'; '.join(warnings)})" if warnings else ""
        super().__init__(f"no Kagi session in browser-fetch's profile{why}; {SIGN_IN}")


class SignedOutError(SearchError):
    """Kagi sent the request to its sign-in page."""

    def __init__(self) -> None:
        """Tell the user to sign in to Kagi again."""
        super().__init__(
            f"Kagi rejected the session in browser-fetch's profile (signed out or expired); "
            f"{SIGN_IN}"
        )


class ChallengeError(SearchError):
    """Kagi answered with a bot challenge."""

    def __init__(self) -> None:
        """Name the bot challenge as the failure."""
        super().__init__("Kagi answered with a bot challenge instead of results")


def fetch_page(query: str, client: fetch.Client, *, since: dt.date | None = None) -> str:
    """Return the HTML of Kagi's results page for the query, from since onward if given.

    Nothing is sent without a Kagi session in the jar. The request never
    follows a redirect: one to the sign-in page or the challenge is the
    answer.
    """
    params = {"q": query} | ({"from_date": since.isoformat()} if since else {})
    url = f"{SEARCH_URL}?{urlencode(params)}"
    if not any(cookie.name == SESSION_COOKIE for cookie in client.cookies(url)):
        raise SessionError(client.warnings)
    try:
        reply = client.get(url)
    except (curl.TransportError, fetch.FetchError) as error:
        raise SearchError(str(error)) from None
    if reply.status in _REDIRECTS:
        location = reply.header("location") or ""
        if "signin" in location or "login" in location:
            raise SignedOutError
        if "turnstile" in location:
            raise ChallengeError
        msg = f"Kagi redirected to {location or 'an unnamed location'}"
        raise SearchError(msg)
    if reply.status != _OK:
        msg = f"Kagi answered HTTP {reply.status}"
        raise SearchError(msg)
    return reply.body.decode("utf-8", errors="replace")


def search(  # noqa: PLR0913 - keyword-only options of the public entry point
    query: str,
    client: fetch.Client,
    *,
    allowed: list[str] | None = None,
    blocked: list[str] | None = None,
    limit: int | None = 10,
    since: dt.date | None = None,
) -> list[Hit]:
    """Return at most limit hits (every hit without one), filtered by domain."""
    page = fetch_page(kagi_query(query, allowed, blocked), client, since=since)
    return filter_hits(parse_page(page), allowed, blocked)[:limit]
