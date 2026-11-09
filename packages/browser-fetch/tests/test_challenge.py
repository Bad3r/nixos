# Copyright (c) 2026 Bad3r
"""Challenge and script-shell detection on captured responses."""

import unittest
from pathlib import Path

from browser_fetch import challenge, convert

FIXTURES = Path(__file__).parent / "fixtures"


def detect(name: str, status: int, headers: dict[str, list[str]] | None = None) -> str | None:
    """Run detection on a fixture the way fetch does."""
    html = (FIXTURES / name).read_text()
    ok = 200 <= status < 300  # noqa: PLR2004 - the 2xx class
    visible = convert.visible_length(convert.html_to_markdown(html)) if ok else None
    return challenge.detect(status, headers or {}, html, visible)


class VendorTest(unittest.TestCase):
    """Bot-protection responses, captured from sites behind each vendor."""

    def test_cloudflare_header(self) -> None:
        """cf-mitigated: challenge is a challenge whatever the body."""
        self.assertEqual(
            challenge.detect(403, {"cf-mitigated": ["challenge"]}, None, None),
            "a Cloudflare challenge",
        )

    def test_cloudflare_body(self) -> None:
        """Indeed's challenge page carries window._cf_chl_opt."""
        self.assertEqual(detect("cloudflare-indeed.txt", 403), "a Cloudflare challenge")

    def test_datadome(self) -> None:
        """Etsy's DataDome block loads its captcha from captcha-delivery.com."""
        self.assertEqual(detect("datadome-etsy.txt", 403), "a DataDome challenge")
        self.assertEqual(
            challenge.detect(403, {"x-dd-b": ["2"]}, "<html></html>", None),
            "a DataDome challenge",
        )

    def test_datadome_header_on_a_normal_page(self) -> None:
        """x-datadome: protected rides ordinary 200 pages, as leboncoin's did."""
        html = (FIXTURES / "example-com.txt").read_text()
        self.assertIsNone(challenge.detect(200, {"x-datadome": ["protected"]}, html, 156))

    def test_perimeterx(self) -> None:
        """Zillow's PerimeterX block sets window._pxAppId and px-captcha."""
        self.assertEqual(detect("perimeterx-zillow.txt", 403), "a PerimeterX challenge")

    def test_akamai_denial_on_200(self) -> None:
        """Lowe's Akamai denial came with status 200 and encoded references."""
        self.assertEqual(detect("akamai-lowes.txt", 200), "an Akamai denial")

    def test_vendor_markers_need_a_block_status(self) -> None:
        """A 200 page that mentions a captcha script is not a challenge."""
        html = (
            "<p>" + "text " * 100 + "</p><script src='https://captcha-delivery.com/x.js'></script>"
        )
        self.assertIsNone(challenge.detect(200, {}, html, 500))


class ShellTest(unittest.TestCase):
    """Pages whose scripts have yet to build them."""

    def test_script_challenge(self) -> None:
        """Reddit's proof-of-work page has scripts and no text."""
        self.assertEqual(detect("reddit-js-challenge.txt", 200), "a page built by scripts")

    def test_short_page_with_text(self) -> None:
        """example.com's one paragraph and script stay with curl."""
        self.assertIsNone(detect("example-com.txt", 200))

    def test_no_scripts(self) -> None:
        """An empty page without scripts is just empty."""
        self.assertIsNone(challenge.detect(200, {}, "<html><body></body></html>", 0))

    def test_error_pages_are_not_shells(self) -> None:
        """A 404 page with scripts stays an HTTP error."""
        html = "<html><body><script>x()</script></body></html>"
        self.assertIsNone(challenge.detect(404, {}, html, None))
