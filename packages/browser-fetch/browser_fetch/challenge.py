# Copyright (c) 2026 Bad3r
"""Responses a real browser has a better chance at than curl.

Each marker comes from a response captured from a site behind that vendor;
tests/fixtures holds the trimmed captures.
"""

from __future__ import annotations

import html as entities
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence

# Fewer visible characters than this, from a page with scripts, is a page
# its scripts have yet to build; example.com's one paragraph has 156.
SHELL_TEXT = 100
BLOCK_STATUSES = range(400, 600)
SHELL = "a page built by scripts"

# Markers that the rendered DOM still shows a challenge, for the browser's wait.
BODY_MARKERS = (
    "window._cf_chl_opt",
    "captcha-delivery.com",
    "px-captcha",
    "window._pxAppId",
    "errors.edgesuite.net",
)


def _values(headers: Mapping[str, Sequence[str]], name: str) -> list[str]:
    return [value.strip().lower() for value in headers.get(name, [])]


def _blocked(headers: Mapping[str, Sequence[str]], html: str) -> str | None:
    """Return the vendor whose block page a 4xx or 5xx response is, or None."""
    if "window._cf_chl_opt" in html:
        return "a Cloudflare challenge"
    # x-datadome: protected rides ordinary pages too; x-dd-b only blocks.
    if headers.get("x-dd-b") or "captcha-delivery.com" in html:
        return "a DataDome challenge"
    if headers.get("x-px-blocked") or "px-captcha" in html or "window._pxAppId" in html:
        return "a PerimeterX challenge"
    return None


def detect(
    status: int,
    headers: Mapping[str, Sequence[str]],
    html: str | None,
    visible: int | None,
) -> str | None:
    """Return why the response needs the browser, or None.

    html is the decoded body when it is HTML, and visible the length of its
    converted text.
    """
    # Cloudflare documents this header on every challenge response.
    if "challenge" in _values(headers, "cf-mitigated"):
        return "a Cloudflare challenge"
    if html is None:
        return None
    vendor = _blocked(headers, html) if status in BLOCK_STATUSES else None
    # Akamai's edge denial page, served with 403 and with 200 alike; its
    # reference link is written in character references.
    if vendor is None and "Access Denied" in html:
        vendor = "an Akamai denial" if "errors.edgesuite.net" in entities.unescape(html) else None
    if (
        vendor is None
        and visible is not None
        and visible < SHELL_TEXT
        and "<script" in html.lower()
    ):
        vendor = SHELL
    return vendor
