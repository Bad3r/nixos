"""HTTP utilities for fetching data from URLs."""

import json
import os
import urllib.parse
import urllib.request
from typing import cast

type JsonValue = None | bool | int | float | str | list[JsonValue] | dict[str, JsonValue]
type JsonObject = dict[str, JsonValue]
type JsonArray = list[JsonValue]


def _require_http_url(url: str) -> None:
    """Reject non-HTTP(S) URLs before handing them to urllib."""
    scheme = urllib.parse.urlparse(url).scheme.lower()
    if scheme not in {"http", "https"}:
        msg = f"Refusing to fetch non-HTTP(S) URL: {url}"
        raise ValueError(msg)


def _github_request(url: str) -> urllib.request.Request:
    """Build an authenticated GitHub API request.

    Uses the GITHUB_TOKEN environment variable so that CI jobs don't hit
    the unauthenticated rate limit (60 req/h to 5 000 req/h).
    """
    _require_http_url(url)
    req = urllib.request.Request(url)  # noqa: S310
    token = os.environ.get("GITHUB_TOKEN", "")
    if token:
        req.add_header("Authorization", f"token {token}")
    return req


# Default user-agent avoids 403s from servers that block Python's default.
DEFAULT_USER_AGENT = "llm-agents-updater"


def fetch_text(url: str, *, timeout: int = 30, user_agent: str = DEFAULT_USER_AGENT) -> str:
    """Fetch text content from a URL.

    Args:
        url: URL to fetch
        timeout: Request timeout in seconds
        user_agent: User-Agent header value

    Returns:
        Response body as text

    Raises:
        urllib.error.URLError: If the request fails

    """
    _require_http_url(url)
    req = (
        _github_request(url) if "api.github.com" in url else urllib.request.Request(url)  # noqa: S310
    )
    req.add_header("User-Agent", user_agent)
    with urllib.request.urlopen(req, timeout=timeout) as response:  # noqa: S310
        data: bytes = response.read()
        return data.decode("utf-8")


def fetch_json(url: str, *, timeout: int = 30) -> JsonObject | JsonArray:
    """Fetch and parse JSON from a URL.

    Args:
        url: URL to fetch
        timeout: Request timeout in seconds

    Returns:
        Parsed JSON data (dict or list)

    Raises:
        urllib.error.URLError: If the request fails
        json.JSONDecodeError: If response is not valid JSON

    """
    text = fetch_text(url, timeout=timeout)
    return cast("JsonObject | JsonArray", json.loads(text))
