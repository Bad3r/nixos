# Copyright (c) 2026 Bad3r
"""The fetch: redirects, cookies per hop and their precedence, the browser, content types."""

import dataclasses
import fcntl
import json
import os
import shutil
import sqlite3
import tempfile
import unittest
import unittest.mock
from pathlib import Path
from typing import Any

from browser_fetch import browser, challenge, curl, fetch, urls
from browser_fetch import cookies as jar

from tests.fakes import PUBLIC_ADDRESS, FakeBrowser, fake_curl, public
from tests.test_cookies import LATER, SCHEMA

FIXTURES = Path(__file__).parent / "fixtures"
HTML = {"Content-Type": "text/html; charset=utf-8"}
PAGE = "<h1>Hello</h1><p>" + "words " * 40 + "</p>"
IDENTITY = curl.Identity("Camoufox/UA", "en-US,en;q=0.9")
URL = "https://a.example/"


class FetchTest(unittest.TestCase):
    """fetch.fetch against a fake curl and a fake browser."""

    def setUp(self) -> None:
        """Create a LibreWolf root with cookies for two hosts, and a fake curl."""
        self.fake, self.holder = fake_curl()
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        root = self.tmp / "librewolf"
        profile = root / "p.default"
        profile.mkdir(parents=True)
        (root / "profiles.ini").write_text("[Profile0]\nName=p\nPath=p.default\nDefault=1\n")
        db = sqlite3.connect(profile / jar.DB_NAME)
        db.execute(SCHEMA)
        db.executemany(
            "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
            " creationTime, isSecure) values ('', ?, ?, ?, ?, ?, 1, 1)",
            [
                ("a", "va", "a.example", "/", LATER),
                ("www", "vw", "www.a.example", "/", LATER),
                ("deep", "vd", "a.example", "/deep", LATER),
                ("b", "vb", "b.example", "/", LATER),
                ("lan", "vl", "10.1.2.3", "/", LATER),
                ("cf", "librewolf", ".a.example", "/", LATER),
            ],
        )
        db.commit()
        db.close()
        patch = unittest.mock.patch.object(jar, "librewolf_root", return_value=root)
        patch.start()
        self.addCleanup(patch.stop)
        self.work = self.tmp / "work"
        self.work.mkdir()
        self.browser = FakeBrowser(identity_value=IDENTITY)
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
            ["a=va; cf=librewolf", "www=vw; cf=librewolf", "www=vw; cf=librewolf"],
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

    def test_browser_cookie_wins_over_librewolf(self) -> None:
        """On the same name, host and path, curl sends the browser's earned cookie."""
        self.browser.own = [
            jar.Cookie("cf", "camoufox", ".a.example", "/", LATER, secure=True, created=9)
        ]
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        fetch.fetch("https://a.example/", self.settings)
        sent = self.cookies_sent()[0]
        self.assertIn("cf=camoufox", sent)
        self.assertNotIn("librewolf", sent)

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
            with (
                self.subTest(url=url),
                unittest.mock.patch.object(jar, "default_profile") as profile,
                self.assertRaises(urls.PrivateAddressError),
            ):
                fetch.fetch(url, settings)
            profile.assert_not_called()
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
        """A challenge is rendered with LibreWolf's jar and the cookies its response set."""
        challenge_page = (FIXTURES / "cloudflare-indeed.txt").read_text()
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 403,
                    "headers": {**HTML, "cf-mitigated": "challenge", "Set-Cookie": "__cf_bm=x"},
                    "body": challenge_page,
                }
            }
        )
        self.browser.rendered = self.rendered()
        page = fetch.fetch("https://a.example/", self.settings)
        (call,) = self.browser.calls or []
        self.assertEqual(call["url"], "https://a.example/")
        self.assertIn("a", [c.name for c in call["librewolf"]])
        self.assertEqual([c.name for c in call["received"]], ["__cf_bm"])
        self.assertEqual(
            (page.via, page.status, page.reason), ("browser", 200, "a Cloudflare challenge")
        )
        self.assertIn("# Hello", page.text)

    def test_unclearable_challenge_is_a_page(self) -> None:
        """A challenge still showing is returned as the page, with the browser's status."""
        self.fake.serve(
            {"https://a.example/": {"status": 403, "headers": {"cf-mitigated": "challenge"}}}
        )
        self.browser.rendered = self.rendered(
            status=403, html="<h1>Additional Verification Required</h1>"
        )
        page = fetch.fetch("https://a.example/", self.settings)
        self.assertEqual((page.outcome, page.status, page.status_text), ("ok", 403, "Forbidden"))
        self.assertIn("Additional Verification Required", page.text)

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
        """A short page with scripts is still the page curl got when the browser fails."""
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
        """--no-cookies reads no LibreWolf profile; the browser's own jar still counts."""
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        self.browser.own = [jar.Cookie("own", "x", "a.example", "/", LATER, secure=True, created=9)]
        cookieless = dataclasses.replace(self.settings, use_cookies=False)
        with unittest.mock.patch.object(jar, "default_profile") as profile:
            fetch.fetch("https://a.example/", cookieless)
        profile.assert_not_called()
        self.assertEqual(self.cookies_sent(), ["own=x"])

    def test_deletion_on_a_redirect_is_not_undone_by_the_stored_jars(self) -> None:
        """A Set-Cookie deletion of a LibreWolf cookie keeps it off every later hop."""
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
        self.assertEqual(self.cookies_sent(), ["a=va; cf=librewolf", "cf=librewolf"])

    def test_deletion_reaches_the_browser_handoff(self) -> None:
        """The deleted cookie's tombstone goes to the browser, and no live copy of it."""
        self.fake.serve(
            {
                "https://a.example/": {
                    "status": 403,
                    "headers": {"cf-mitigated": "challenge", "Set-Cookie": "a=; Max-Age=0"},
                }
            }
        )
        self.browser.rendered = browser.Rendered("https://a.example/", 200, "text/html", PAGE)
        fetch.fetch("https://a.example/", self.settings)
        (call,) = self.browser.calls or []
        handed = browser.injection([], call["librewolf"], call["received"], URL, jar.now_ms())
        self.assertNotIn("a", [c.name for c in handed])
        self.assertIn("cf", [c.name for c in handed])

    def test_expired_browser_cookie_does_not_hide_librewolfs(self) -> None:
        """An expired Camoufox row loses to LibreWolf's live cookie of the same key."""
        self.browser.own = [
            jar.Cookie("cf", "camoufox", ".a.example", "/", 1, secure=True, created=9)
        ]
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        fetch.fetch("https://a.example/", self.settings)
        self.assertIn("cf=librewolf", self.cookies_sent()[0])

    def test_killed_render_leaves_nothing_for_a_curl_only_fetch(self) -> None:
        """After a SIGKILLed render, --no-cookies --browser never sends no injected cookie.

        The profile holds the injected row and the journal, as a render killed
        between add_cookies and its purge leaves them; the jar read purges
        first and consumes the journal.
        """
        state = self.tmp / "state"
        profile = state / browser.PROFILE
        profile.mkdir(parents=True)
        (state / browser.FINGERPRINT).write_text(
            json.dumps(
                {"browser": "v", "headers": {"user-agent": "UA", "accept-language": "en-US"}}
            )
        )
        db = sqlite3.connect(profile / jar.DB_NAME)
        db.execute(SCHEMA)
        db.executemany(
            "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
            " creationTime, isSecure) values ('', ?, ?, '.a.example', '/', ?, 1, 1)",
            [("lent", "LIBREWOLF-CANARY", LATER), ("earned", "own", LATER)],
        )
        db.commit()
        db.close()
        journal = [
            {
                "name": "lent",
                "host": ".a.example",
                "path": "/",
                "digest": browser.digest("LIBREWOLF-CANARY"),
            }
        ]
        (state / browser.JOURNAL).write_text(json.dumps(journal))
        camoufox = browser.Camoufox(
            browser.Tools("unshare", "session", "v", "pasta"), state, self.work
        )
        settings = dataclasses.replace(
            self.settings, browser=camoufox, use_cookies=False, browser_mode="never"
        )
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        page = fetch.fetch("https://a.example/", settings)
        self.assertEqual((page.outcome, page.via), ("ok", "curl"))
        self.assertEqual(self.cookies_sent(), ["earned=own"])
        self.assertFalse((state / browser.JOURNAL).exists())

    def test_a_busy_profile_is_left_out_not_read(self) -> None:
        """While another fetch's session holds the profile, its jar is not read at all."""
        state = self.tmp / "state"
        profile = state / browser.PROFILE
        profile.mkdir(parents=True)
        db = sqlite3.connect(profile / jar.DB_NAME)
        db.execute(SCHEMA)
        db.execute(
            "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
            " creationTime, isSecure) values ('', 'lent', 'x', '.a.example', '/', ?, 1, 1)",
            (LATER,),
        )
        db.commit()
        db.close()
        holder = os.open(state / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(holder, fcntl.LOCK_EX)
        self.addCleanup(os.close, holder)
        camoufox = browser.Camoufox(
            browser.Tools("unshare", "session", "v", "pasta"), state, self.work
        )
        settings = dataclasses.replace(
            self.settings, browser=camoufox, use_cookies=False, browser_mode="never"
        )
        self.fake.serve({"https://a.example/": {"status": 200, "headers": HTML, "body": PAGE}})
        with (
            unittest.mock.patch.object(camoufox, "identity", return_value=None),
            unittest.mock.patch.object(browser, "LOCK_SECONDS", 0.3),
        ):
            page = fetch.fetch("https://a.example/", settings)
        self.assertEqual(self.cookies_sent(), [""])
        self.assertIn("busy", " ".join(page.notes))
