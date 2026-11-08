# Copyright (c) 2026 Bad3r
"""The fetch: redirects, cookies per hop and their precedence, the browser, content types."""

import dataclasses
import fcntl
import os
import shutil
import tempfile
import unittest
import unittest.mock
from pathlib import Path
from typing import Any

from browser_fetch import browser, challenge, convert, curl, fetch, urls
from browser_fetch import cookies as jar

from tests.fakes import PUBLIC_ADDRESS, FakeBrowser, fake_curl, public
from tests.test_cookies import LATER

FIXTURES = Path(__file__).parent / "fixtures"
HTML = {"Content-Type": "text/html; charset=utf-8"}
PAGE = "<h1>Hello</h1><p>" + "words " * 40 + "</p>"
IDENTITY = curl.Identity("Camoufox/UA", "en-US,en;q=0.9")
URL = "https://a.example/"
BUSY = "another fetch or a login kept the browser profile busy; try again"


def profile_cookie(name: str, value: str, host: str, path: str = "/") -> jar.Cookie:
    """A persistent cookie of the profile's jar."""
    return jar.Cookie(name, value, host, path, LATER, secure=True, created=1)


class FetchTest(unittest.TestCase):
    """fetch.fetch against a fake curl and a fake browser."""

    def setUp(self) -> None:
        """A profile jar with cookies for two hosts, a fake browser and a fake curl."""
        self.fake, self.holder = fake_curl()
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        self.work = self.tmp / "work"
        self.work.mkdir()
        self.browser = FakeBrowser(
            identity_value=IDENTITY,
            own=[
                profile_cookie("a", "va", "a.example"),
                profile_cookie("www", "vw", "www.a.example"),
                profile_cookie("deep", "vd", "a.example", "/deep"),
                profile_cookie("b", "vb", "b.example"),
                profile_cookie("lan", "vl", "10.1.2.3"),
                profile_cookie("cf", "earned", ".a.example"),
            ],
        )
        self.settings = fetch.Settings(
            curl=self.fake.path,
            browser=self.browser,
            workdir=self.work,
            save_dir=self.tmp / "saved",
            resolve=public,
        )

    def tearDown(self) -> None:
        """Remove the fakes."""
        self.holder.cleanup()
        shutil.rmtree(self.tmp)

    def cookies_sent(self) -> list[str]:
        """Return the Cookie header of each curl call, or ""."""
        sent: list[str] = []
        for call in self.fake.calls():
            lines = [line for line in call["config"].splitlines() if "Cookie: " in line]
            sent.append(lines[0].split("Cookie: ", 1)[1].rstrip('"') if lines else "")
        return sent

    def test_same_host_redirects_are_followed_with_fresh_cookies(self) -> None:
        """Each hop carries the cookies of its own URL."""
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 301,
                    "headers": {"Location": "https://www.a.example/x"},
                },
                "https://www.a.example/x": {"status": 302, "headers": {"Location": "/deep/y"}},
                "https://www.a.example/deep/y": {"status": 200, "headers": HTML, "body": PAGE},
            }
        )
        page = fetch.fetch("http://a.example/", self.settings)
        self.assertEqual(page.outcome, "ok")
        self.assertEqual(
            self.cookies_sent(),
            ["a=va; cf=earned", "www=vw; cf=earned", "www=vw; cf=earned"],
        )
        self.assertIn("# Hello", page.text)

    def test_cookie_set_on_a_redirect_reaches_the_next_hop(self) -> None:
        """A cookie-gated redirect reaches the page, as in a browser."""
        self.fake.serve(
            {
                "https://a.example/gate": {
                    "status": 302,
                    "headers": {"Location": "/", "Set-Cookie": "gate=passed; Path=/"},
                },
                "https://a.example/": {"status": 200, "headers": HTML, "body": PAGE},
            }
        )
        page = fetch.fetch("https://a.example/gate", self.settings)
        self.assertEqual(page.outcome, "ok")
        self.assertIn("gate=passed", self.cookies_sent()[1])

    def test_identity_headers_reach_curl(self) -> None:
        """Curl sends the browser fingerprint's User-Agent and languages."""
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        fetch.fetch("https://a.example/", self.settings)
        config = self.fake.calls()[0]["config"]
        self.assertIn('header = "User-Agent: Camoufox/UA"', config)
        self.assertIn('header = "Accept-Language: en-US,en;q=0.9"', config)

    def test_private_hosts_are_refused_before_anything_is_read_or_sent(self) -> None:
        """A literal or a name resolving privately is refused: no request, cookie or browser."""
        resolved = {"lan.example": ["10.1.2.3"], "loop.example": ["127.0.0.1"]}

        def resolve(host: str, _port: int) -> list[str]:
            return resolved.get(host, [PUBLIC_ADDRESS])

        settings = dataclasses.replace(self.settings, resolve=resolve)
        for url in ("https://10.1.2.3/", "https://lan.example/", "https://loop.example/"):
            with self.subTest(url=url), self.assertRaises(urls.PrivateAddressError):
                fetch.fetch(url, settings)
        self.assertEqual((self.browser.reads, self.browser.stored), (0, []))
        self.assertEqual(self.fake.calls(), [])
        self.assertIsNone(self.browser.calls)

    def test_each_hop_is_checked_and_pinned_against_rebinding(self) -> None:
        """A same-host redirect is resolved again; a private answer stops it before curl runs."""
        self.fake.serve({"https://a.example/": {"status": 302, "headers": {"Location": "/next"}}})
        answers = iter([[PUBLIC_ADDRESS], [PUBLIC_ADDRESS], ["127.0.0.1"]])

        def resolve(_host: str, _port: int) -> list[str]:
            return next(answers)

        settings = dataclasses.replace(self.settings, resolve=resolve)
        with self.assertRaises(urls.PrivateAddressError):
            fetch.fetch("https://a.example/", settings)
        (call,) = self.fake.calls()
        argv = call["argv"]
        self.assertEqual(argv[argv.index("--resolve") + 1], f"a.example:443:{PUBLIC_ADDRESS}")

    def test_cross_host_redirect_is_reported(self) -> None:
        """A redirect to another host stops with the redirect and sends nothing there."""
        self.fake.serve(
            {"https://a.example/": {"status": 302, "headers": {"Location": "https://b.example/z"}}}
        )
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual(
            (page.outcome, page.status, page.redirect_from, page.redirect_to),
            ("redirect", 302, "https://a.example/", "https://b.example/z"),
        )
        self.assertEqual(len(self.fake.calls()), 1)

    def test_redirect_without_location(self) -> None:
        """A redirect status without a Location is an HTTP error."""
        self.fake.serve({"https://a.example/": {"status": 301}})
        self.assertEqual(fetch.fetch("https://a.example/", self.settings).outcome, "http_error")

    def test_too_many_redirects(self) -> None:
        """Eleven requests at most, as WebFetch makes."""
        self.fake.serve(
            {"https://a.example/": {"status": 302, "headers": {"Location": "https://a.example/"}}}
        )
        with self.assertRaisesRegex(fetch.FetchError, "exceeded 10"):
            fetch.fetch("https://a.example/", self.settings)
        self.assertEqual(len(self.fake.calls()), 11)

    def test_http_error(self) -> None:
        """A plain 404 is an HTTP error with no browser."""
        self.fake.serve(
            {"https://a.example/": {"status": 404, "headers": HTML, "body": "<p>nope</p>"}}
        )
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertIsNone(self.browser.calls)
        self.assertEqual((page.outcome, page.status), ("http_error", 404))

    def test_retry_after(self) -> None:
        """Retry-After passes on only as up to six digits."""
        self.fake.serve(
            {
                "https://a.example/": {"status": 429, "headers": {"Retry-After": "120"}},
                "https://b.example/": {"status": 429, "headers": {"Retry-After": "Fri, 07 Nov"}},
            }
        )
        self.assertEqual(fetch.fetch("https://a.example/", self.settings).retry_after, "120")
        self.assertIsNone(fetch.fetch("https://b.example/", self.settings).retry_after)

    def rendered(self, **fields: Any) -> browser.Rendered:  # noqa: ANN401
        """Return a browser result."""
        values: dict[str, Any] = {
            "url": "https://a.example/",
            "status": 200,
            "content_type": "text/html",
            "html": PAGE,
        }
        values.update(fields)
        return browser.Rendered(**values)

    def test_challenge_goes_to_the_browser_with_all_cookies_seen(self) -> None:
        """A challenge is rendered on the profile, given the cookies its response set.

        They are written as the response arrives, before the browser starts;
        one the profile was too busy to take then is the render's to write.
        """
        challenge_page = (FIXTURES / "cloudflare-indeed.txt").read_text()
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 403,
                    "headers": {
                        **HTML,
                        "cf-mitigated": "challenge",
                        "Set-Cookie": "__cf_bm=x; Max-Age=1800; Secure",
                    },
                    "body": challenge_page,
                }
            }
        )
        self.browser.rendered = self.rendered()
        page = fetch.fetch("https://a.example/", self.settings)
        (call,) = self.browser.calls or []
        self.assertEqual(call["url"], "https://a.example/")
        self.assertEqual((call["pending"], call["keep"]), ([], True))
        self.assertEqual([[c.name for c in batch] for batch in self.browser.stored], [["__cf_bm"]])
        self.assertEqual(
            (page.via, page.status, page.reason), ("browser", 200, "a Cloudflare challenge")
        )
        self.assertIn("# Hello", page.text)
        self.browser.store_error = browser.BrowserError(BUSY)
        page = fetch.fetch("https://a.example/", self.settings)
        call = (self.browser.calls or [])[-1]
        self.assertEqual([c.name for c in call["pending"]], ["__cf_bm"])
        self.assertEqual(page.warnings, [])

    def test_browser_error_status_is_an_http_error(self) -> None:
        """A document the browser ends on outside 2xx is an HTTP error, as from curl.

        WebFetch reads no body of an error status, so nothing is converted or saved.
        """
        self.fake.serve(
            {"https://a.example/": {"status": 403, "headers": {"cf-mitigated": "challenge"}}}
        )
        always = dataclasses.replace(self.settings, browser_mode="always")
        for settings, status in ((self.settings, 403), (self.settings, 503), (always, 404)):
            with self.subTest(mode=settings.browser_mode, status=status):
                self.browser.rendered = self.rendered(
                    status=status, html=None, body=b"\x89PNG-bytes", content_type="image/png"
                )
                page = fetch.fetch("https://a.example/", settings)
                self.assertEqual(
                    (page.outcome, page.status, page.via, page.text, page.saved_path),
                    ("http_error", status, "browser", "", None),
                )
        self.assertEqual(len(self.fake.calls()), 2)

    def test_unclearable_challenge_is_an_http_error(self) -> None:
        """A challenge still showing on a 403 is reported as the 403, as curl's would be."""
        self.fake.serve(
            {"https://a.example/": {"status": 403, "headers": {"cf-mitigated": "challenge"}}}
        )
        self.browser.rendered = self.rendered(
            status=403, html="<h1>Additional Verification Required</h1>"
        )
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual(
            (page.outcome, page.status, page.status_text, page.reason),
            ("http_error", 403, "Forbidden", "a Cloudflare challenge"),
        )

    def test_browser_dom_is_not_decoded_twice(self) -> None:
        """The DOM is text: a meta charset in it no longer applies."""
        self.fake.serve(
            {"https://a.example/": {"status": 200, "headers": HTML, "body": "<script></script>"}}
        )
        dom = (
            '<html><head><meta charset="windows-1252"></head>'
            "<body><p>café “quoted” naïve</p></body></html>"
        )
        self.browser.rendered = self.rendered(html=dom)
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertIn("café “quoted” naïve", page.text)

    def test_browser_document_keeps_its_bytes(self) -> None:
        """A non-HTML document the browser ended on is saved from its bytes, not DOM text."""
        self.fake.serve(
            {"https://a.example/": {"status": 403, "headers": {"cf-mitigated": "challenge"}}}
        )
        self.browser.rendered = self.rendered(
            html=None, body=b"\x89PNG-bytes", content_type="image/png"
        )
        page = fetch.fetch("https://a.example/", self.settings)
        if page.saved_path is None:
            self.fail("nothing was saved")
        self.assertEqual(Path(page.saved_path).read_bytes(), b"\x89PNG-bytes")

    def test_blocked_browser_hop_is_a_redirect(self) -> None:
        """A hop the browser's guard stopped is reported as WebFetch reports a redirect."""
        self.fake.serve(
            {"https://a.example/": {"status": 200, "headers": HTML, "body": "<script></script>"}}
        )
        self.browser.rendered = self.rendered(
            blocked=browser.Blocked("https://a.example/", "https://login.b.example/", 302)
        )
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual(
            (page.outcome, page.status, page.redirect_from, page.redirect_to),
            ("redirect", 302, "https://a.example/", "https://login.b.example/"),
        )

    def test_failed_browser_keeps_a_script_built_page(self) -> None:
        """A short page with scripts is still the page curl got when the browser fails.

        The README's documented outcome; the failure is a warning, since the
        page may lack what its scripts would have built.
        """
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 200,
                    "headers": HTML,
                    "body": "<p>hi</p><script></script>",
                }
            }
        )
        self.browser.error = browser.BrowserError("no display")
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual((page.outcome, page.via, page.text), ("ok", "curl", "hi"))
        self.assertEqual(
            page.warnings,
            ["the browser could not render the page, so curl's copy stands: no display"],
        )

    def test_failed_browser_on_a_challenge_is_an_error(self) -> None:
        """A challenge the browser could not even try is a failure, not the block page."""
        self.fake.serve(
            {"https://a.example/": {"status": 403, "headers": {"cf-mitigated": "challenge"}}}
        )
        self.browser.error = browser.BrowserError("no display")
        with self.assertRaises(browser.BrowserError):
            fetch.fetch("https://a.example/", self.settings)

    def test_browser_never(self) -> None:
        """With the browser off, a script shell is returned as curl got it."""
        self.fake.serve(
            {"https://a.example/": {"status": 200, "headers": HTML, "body": "<script></script>"}}
        )
        never = dataclasses.replace(self.settings, browser_mode="never")
        page = fetch.fetch("https://a.example/", never)
        self.assertIsNone(self.browser.calls)
        self.assertEqual((page.outcome, page.via, page.text), ("ok", "curl", ""))

    def test_shell_reason_constant(self) -> None:
        """The fallback names a script-built page by the challenge module's reason."""
        self.assertEqual(challenge.SHELL, "a page built by scripts")

    def test_text_types_pass_through(self) -> None:
        """JSON, plain text and Markdown reach the model as they came."""
        body = '{"a": 1}'
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 200,
                    "headers": {"Content-Type": "application/json"},
                    "body": body,
                }
            }
        )
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual((page.text, page.saved_path), (body, None))

    def test_binary_is_saved(self) -> None:
        """A binary body is saved privately and its bytes decoded as WebFetch does."""
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 200,
                    "headers": {"Content-Type": "image/png"},
                    "body": "PNGDATA",
                }
            }
        )
        page = fetch.fetch("https://a.example/", self.settings)
        if page.saved_path is None:
            self.fail("nothing was saved")
        saved = Path(page.saved_path)
        self.assertEqual(saved.read_bytes(), b"PNGDATA")
        self.assertEqual(saved.suffix, ".png")
        self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
        self.assertEqual(page.text, "PNGDATA")
        self.assertFalse(page.converted)

    def test_no_cookies(self) -> None:
        """--no-cookies reads and writes no jar; the fetch's own cookies still go on later hops.

        A fallback gets a throwaway profile (keep is off).
        """
        self.fake.serve(
            {
                "https://a.example/gate": {
                    "status": 302,
                    "headers": {"Location": "/", "Set-Cookie": "gate=1; Max-Age=60; Secure"},
                },
                "https://a.example/": {"status": 403, "headers": {"cf-mitigated": "challenge"}},
            }
        )
        self.browser.rendered = self.rendered()
        cookieless = dataclasses.replace(self.settings, use_cookies=False)
        fetch.fetch("https://a.example/gate", cookieless)
        self.assertEqual(self.cookies_sent(), ["", "gate=1"])
        self.assertEqual((self.browser.reads, self.browser.stored), (0, []))
        (call,) = self.browser.calls or []
        self.assertFalse(call["keep"])

    def test_deletion_on_a_redirect_is_not_undone_by_the_profile(self) -> None:
        """A Set-Cookie deletion of a profile cookie keeps it off later hops and leaves its row."""
        self.fake.serve(
            {
                "https://a.example/out": {
                    "status": 302,
                    "headers": {"Location": "/", "Set-Cookie": "a=; Path=/; Max-Age=0"},
                },
                "https://a.example/": {"status": 200, "headers": HTML, "body": PAGE},
            }
        )
        fetch.fetch("https://a.example/out", self.settings)
        self.assertEqual(self.cookies_sent(), ["a=va; cf=earned", "cf=earned"])
        ((deleted,),) = self.browser.stored
        self.assertEqual((deleted.name, deleted.expired(jar.now_us() // 1000)), ("a", True))

    def test_received_cookie_wins_over_the_profile(self) -> None:
        """A cookie a response set replaces the profile's of its key on the next hop."""
        self.fake.serve(
            {
                "https://a.example/next": {
                    "status": 302,
                    "headers": {
                        "Location": "/",
                        "Set-Cookie": "cf=fresh; Domain=a.example; Path=/; Max-Age=60; Secure",
                    },
                },
                "https://a.example/": {"status": 200, "headers": HTML, "body": PAGE},
            }
        )
        fetch.fetch("https://a.example/next", self.settings)
        self.assertEqual(self.cookies_sent(), ["a=va; cf=earned", "a=va; cf=fresh"])

    def test_received_cookies_are_saved_before_the_fetch_returns(self) -> None:
        """Every change a response made is written once, persistent or session alike.

        The jar's write drops the session cookie (test_cookies), but it may
        replace a stored row, so it goes too.
        """
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 200,
                    "headers": {**HTML, "Set-Cookie": "sid=1; Max-Age=60; Secure"},
                    "body": PAGE,
                },
            }
        )
        fetch.fetch("https://a.example/", self.settings)
        self.assertEqual([[c.name for c in batch] for batch in self.browser.stored], [["sid"]])

    def test_cookies_are_saved_when_the_fetch_fails(self) -> None:
        """A redirect's cookies are written even when the next hop fails."""
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 302,
                    "headers": {"Location": "/next", "Set-Cookie": "sid=1; Max-Age=60; Secure"},
                },
            }
        )
        with self.assertRaises(curl.TransportError):
            fetch.fetch("https://a.example/", self.settings)
        self.assertEqual([[c.name for c in batch] for batch in self.browser.stored], [["sid"]])

    def test_overlapping_fetches_write_in_arrival_order(self) -> None:
        """A response's cookies land as it arrives, so a later deletion by another fetch stands.

        Fetch A receives sid=rotated and converts its page; meanwhile fetch B
        receives the deletion of sid. Gecko applies them in that order,
        which leaves no sid (Codex's lost update had A write it back last).
        """
        state = self.tmp / "state"
        camoufox = self.camoufox(state)
        settings = dataclasses.replace(self.settings, browser=camoufox, browser_mode="never")
        self.fake.serve(
            {
                "https://a.example/login": {
                    "status": 200,
                    "headers": {**HTML, "Set-Cookie": "sid=rotated; Max-Age=600; Secure; Path=/"},
                    "body": PAGE,
                },
                "https://a.example/logout": {
                    "status": 200,
                    "headers": {**HTML, "Set-Cookie": "sid=; Max-Age=0; Secure; Path=/"},
                    "body": PAGE,
                },
            }
        )
        convert_page = convert.html_to_markdown
        started: list[str] = []

        def converting(html: str, seconds: float) -> str:
            if not started:
                started.append("logout")
                fetch.fetch("https://a.example/logout", settings)
            return convert_page(html, seconds)

        with (
            unittest.mock.patch.object(camoufox, "identity", return_value=None),
            unittest.mock.patch.object(convert, "html_to_markdown", side_effect=converting),
        ):
            fetch.fetch("https://a.example/login", settings)
        self.assertEqual(jar.read(state / browser.PROFILE / jar.DB_NAME), [])

    def test_cookies_of_a_transfer_cut_short_are_saved(self) -> None:
        """Set-Cookie headers that came before curl gave up reach the jar, then the fetch fails."""
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 200,
                    "exit": 63,
                    "headers": {
                        **HTML,
                        "Set-Cookie": ["a=; Path=/; Max-Age=0", "fresh=1; Max-Age=60; Secure"],
                    },
                },
            }
        )
        with self.assertRaisesRegex(curl.TransportError, "larger than"):
            fetch.fetch("https://a.example/", self.settings)
        ((deleted, fresh),) = self.browser.stored
        self.assertEqual((deleted.name, deleted.expired(jar.now_us() // 1000)), ("a", True))
        self.assertEqual((fresh.name, fresh.value), ("fresh", "1"))

    def test_unsaved_cookies_are_reported(self) -> None:
        """A profile still busy at the write leaves a warning on the page, or on the failure."""
        self.browser.store_error = browser.BrowserError(BUSY)
        set_cookie = {"Set-Cookie": "sid=1; Max-Age=60; Secure"}
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 200,
                    "headers": {**HTML, **set_cookie},
                    "body": PAGE,
                },
                "https://b.example/": {"status": 302, "headers": {"Location": "/x", **set_cookie}},
            }
        )
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual(
            (page.outcome, page.warnings), ("ok", [f"1 cookie changes were not saved: {BUSY}"])
        )
        with self.assertRaises(curl.TransportError) as failed:
            fetch.fetch("https://b.example/", self.settings)
        self.assertEqual(failed.exception.__notes__, [f"1 cookie changes were not saved: {BUSY}"])

    def test_deletion_received_while_the_jar_was_busy_is_saved(self) -> None:
        """With the jar unread, a deletion still goes to the profile, or is reported unsaved."""
        self.browser.jar_error = browser.BrowserError(BUSY)
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 200,
                    "headers": {**HTML, "Set-Cookie": "a=; Path=/; Max-Age=0"},
                    "body": PAGE,
                },
            }
        )
        page = fetch.fetch("https://a.example/", self.settings)
        ((deleted,),) = self.browser.stored
        self.assertEqual((deleted.name, deleted.expired(jar.now_us() // 1000)), ("a", True))
        self.assertEqual(page.warnings, [f"no cookies were read: {BUSY}"])
        self.browser.store_error = browser.BrowserError(BUSY)
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual(page.warnings[-1], f"1 cookie changes were not saved: {BUSY}")

    def test_unreadable_jar_is_an_error(self) -> None:
        """A database at another schema or corrupt fails the fetch before any request."""
        self.browser.jar_error = jar.CookieError("schema version 18")
        with self.assertRaisesRegex(jar.CookieError, "schema version 18"):
            fetch.fetch("https://a.example/", self.settings)
        self.assertEqual(self.fake.calls(), [])

    def camoufox(self, state: Path) -> browser.Camoufox:
        """The real browser state handling, with no browser run."""
        return browser.Camoufox(browser.Tools("unshare", "session", "v", "pasta"), state, self.work)

    def test_profile_cookies_reach_the_next_fetch(self) -> None:
        """A fetch's persistent cookie is in the profile for the next; its session cookie is not."""
        camoufox = self.camoufox(self.tmp / "state")
        settings = dataclasses.replace(self.settings, browser=camoufox, browser_mode="never")
        self.fake.serve(
            {
                "https://a.example/set": {
                    "status": 200,
                    "headers": {
                        **HTML,
                        "Set-Cookie": [
                            "kept=1; Max-Age=600; Secure; Path=/",
                            "fleeting=1; Secure; Path=/",
                        ],
                    },
                    "body": PAGE,
                },
                "https://a.example/": {"status": 200, "headers": HTML, "body": PAGE},
            }
        )
        with unittest.mock.patch.object(camoufox, "identity", return_value=None):
            fetch.fetch("https://a.example/set", settings)
            fetch.fetch("https://a.example/", settings)
        self.assertEqual(self.cookies_sent(), ["", "kept=1"])

    def test_a_busy_profile_is_left_out_not_read(self) -> None:
        """While another fetch's session holds the profile, the jar is not read, and it says so."""
        state = self.tmp / "state"
        jar.store(
            state / browser.PROFILE / jar.DB_NAME,
            [profile_cookie("lent", "x", ".a.example")],
            jar.now_us(),
        )
        holder = os.open(state / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(holder, fcntl.LOCK_EX)
        self.addCleanup(os.close, holder)
        camoufox = self.camoufox(state)
        settings = dataclasses.replace(self.settings, browser=camoufox, browser_mode="never")
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        with (
            unittest.mock.patch.object(camoufox, "identity", return_value=None),
            unittest.mock.patch.object(browser, "JAR_LOCK_SECONDS", 0.3),
        ):
            page = fetch.fetch("https://a.example/", settings)
        self.assertEqual(self.cookies_sent(), [""])
        self.assertEqual(page.warnings, [f"no cookies were read: {BUSY}"])

    def test_browser_only_fetch_leaves_the_jar_to_the_browser(self) -> None:
        """--browser always reads no jar for curl, so a busy profile warns of nothing unread.

        Camoufox loads the profile itself once the render's lock is its.
        """
        self.browser.jar_error = browser.BrowserError(BUSY)
        self.browser.rendered = self.rendered()
        always = dataclasses.replace(self.settings, browser_mode="always")
        page = fetch.fetch("https://a.example/", always)
        self.assertEqual((page.via, page.warnings, self.browser.reads), ("browser", [], 0))

    def test_curl_only_fetch_never_draws_a_fingerprint(self) -> None:
        """--browser never asks for a stored fingerprint only."""
        never = dataclasses.replace(self.settings, browser_mode="never")
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        fetch.fetch("https://a.example/", never)
        self.assertEqual(self.browser.generated, [False])

    def test_fingerprint_failure_falls_back_to_the_profile_headers(self) -> None:
        """A fingerprint that cannot be drawn leaves curl's own headers, and the fetch goes on."""
        self.browser.identity_error = browser.BrowserError("no user namespaces")
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual((page.outcome, page.via), ("ok", "curl"))
        self.assertNotIn("User-Agent", self.fake.calls()[0]["config"])
        self.assertIn("no user namespaces", " ".join(page.notes))
