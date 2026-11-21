# Copyright (c) 2026 Bad3r
"""web.run requests answered from fake Kagi hits and fake pages."""

import base64
import contextlib
import datetime as dt
import fcntl
import io
import json
import os
import stat
import tempfile
import threading
import time
import unittest
import unittest.mock
from pathlib import Path
from typing import cast, override

from kagi_search import cli, client, fetch, pdf, webrun
from kagi_search.page import Hit

from tests import pdfs, sandbox

SEPARATOR = "-" * 80 + "\n"
SMALL_TOKENS = 2000
NOW = dt.datetime(2026, 11, 8, 12, 0, tzinfo=dt.UTC)
SESSION = "019a-session"

LIX_URL = "https://lix.systems/blog/2026-10-13-lix-2.96-release/"
LIX_TITLE = "Lix | Announcing Lix 2.96 \u201cBingsu\u201d"
# Markup that renders to lines L0 to L17 of the captured open of LIX_URL.
LIX_HTML = """<!doctype html><html><head>
<title>Lix | Announcing Lix 2.96 &ldquo;Bingsu&rdquo;</title>
<script>document.write("<p>never</p>")</script><style>p { color: red }</style></head>
<body><nav><a href="/">Home</a> <a href="/blog/">Blog</a></nav><main>
<h2>Announcing Lix 2.96 \u201cBingsu\u201d</h2>
<p>Oct 13, 2026</p>
<p>We at the Lix team are proud to announce our seventh major release, version 2.96
\u201cBingsu\u201d.</p>
<p>This release focuses on security, debugger support, quality-of-life improvements, and
continues the work towards both the new <a href="https://capnproto.org/rpc.html">Cap\u2019n\u2019Proto
RPC</a> protocol and Rust support.</p>
<blockquote><a href="https://en.wikipedia.org/wiki/Bingsu">Bingsu</a> is a milk-based Korean shaved
ice dessert with sweet toppings that may include chopped fruit, condensed milk, fruit syrup, tteok,
and red beans.</blockquote>
<div>Lix is a Nix implementation focused on reliability, predictability, friendliness, developed by
a community of people from around the world. We have long term plans to incrementally evolve Nix to
work in more places, to make it more reliable and secure, and to update the language and semantics
to correct past mistakes and reduce errors, all the while providing an amazing tooling
experience.</div>
<h2>Upgrading from CppNix or previous Lix versions</h2>
<p>WARNING: We do not recommend to use <code>nix upgrade-nix</code>, please follow the instructions
in <a href="/install/">https://lix.systems/install/</a> with the Lix\u2019s upgrade shell
script.</p>
<div>The upgrade procedure depends on how you installed Lix or CppNix, and is fully described in the
<a href="https://lix.systems/install/">Lix installation guide</a>.</div>
<p>If you are using Lix from nixpkgs on NixOS, you just need to upgrade your nixpkgs once the
upgrade pull request has passed through the build farm into your channel; no other action is
required.</p>
<p>If you want to help us test the next version of Lix, consider running <code>main</code> by
following the <a href="https://wiki.lix.systems/beta">beta guide</a>.</p>
</main><footer><a href="/governance/">Our Governance</a></footer></body></html>"""
LIX_LINES = [
    "L0: ## Announcing Lix 2.96 \u201cBingsu\u201d",
    "L1: ",
    "L2: Oct 13, 2026",
    "L3: ",
    (
        "L4: We at the Lix team are proud to announce our seventh major release, version 2.96 "
        "\u201cBingsu\u201d."
    ),
    "L5: ",
    (
        "L6: This release focuses on security, debugger support, quality-of-life improvements, and "
        "continues the work towards both the new \u30100\u2020Cap\u2019n\u2019Proto RPC\u2020"
        "capnproto.org\u3011 protocol and Rust support."
    ),
    "L7: ",
    (
        "L8: > \u30101\u2020Bingsu\u2020en.wikipedia.org\u3011 is a milk-based Korean shaved ice "
        "dessert with sweet toppings that may include chopped fruit, condensed milk, fruit syrup, "
        "tteok, and red beans."
    ),
    (
        "L9: Lix is a Nix implementation focused on reliability, predictability, friendliness, "
        "developed by a community of people from around the world. We have long term plans to "
        "incrementally evolve Nix to work in more places, to make it more reliable and secure, and "
        "to update the language and semantics to correct past mistakes and reduce errors, all the "
        "while providing an amazing tooling experience."
    ),
    "L10: ## Upgrading from CppNix or previous Lix versions",
    "L11: ",
    (
        "L12: WARNING: We do not recommend to use `nix upgrade-nix`, please follow the "
        "instructions in \u30102\u2020https://lix.systems/install/\u3011 with the "
        "Lix\u2019s upgrade shell script."
    ),
    "L13: ",
    (
        "L14: The upgrade procedure depends on how you installed Lix or CppNix, and is fully "
        "described in the \u30102\u2020Lix installation guide\u3011."
    ),
    (
        "L15: If you are using Lix from nixpkgs on NixOS, you just need to upgrade your nixpkgs "
        "once the upgrade pull request has passed through the build farm into your channel; "
        "no other action is required."
    ),
    "L16: ",
    (
        "L17: If you want to help us test the next version of Lix, consider running `main` by "
        "following the \u30103\u2020beta guide\u2020wiki.lix.systems\u3011."
    ),
]
MANUAL_URL = "https://docs.lix.systems/manual/lix/stable/release-notes/rl-2.96.html"
MANUAL_TITLE = "Lix 2.96 (2026-10-13) - Lix Reference Manual"
MANUAL_HTML = f"<title>{MANUAL_TITLE}</title><h1>Lix 2.96</h1><p>Changes in Lix 2.96.</p>"
GUIX_HITS = [
    Hit(
        "guix - MyNixOS",
        "https://mynixos.com/nixpkgs/package/guix",
        "GNU Guix is a purely functional package manager for the GNU system, and a distribution "
        "thereof.",
    ),
    Hit(
        "GNU Guix - Meta Package Manager",
        "https://mpm.run/managers/guix/",
        "GNU Guix, GNU\u2019s functional package manager.",
    ),
]


def html(url: str, body: str, *, redirected: bool = False) -> fetch.Page:
    """Return an HTML page as the fetcher hands it over."""
    return fetch.Page(url, "text/html", body, redirected=redirected)


class FakeSearch:
    """Answer every query with fixed hits and record the calls."""

    def __init__(self, hits: list[Hit] | Exception) -> None:
        """Keep the hits to return, or the error to raise."""
        self.hits = hits
        self.calls: list[tuple[str, list[str] | None, list[str] | None, int]] = []
        self.since: list[dt.date | None] = []
        self.until: list[float] = []

    def __call__(  # noqa: PLR0913 - the Searcher's options
        self,
        query: str,
        *,
        allowed: list[str] | None,
        blocked: list[str] | None,
        limit: int,
        since: dt.date | None,
        until: float,
    ) -> list[Hit]:
        """Record the call and answer it."""
        self.calls.append((query, allowed, blocked, limit))
        self.since.append(since)
        self.until.append(until)
        if isinstance(self.hits, Exception):
            raise self.hits
        return self.hits


class FakeFetch:
    """Serve pages from a table and record the URLs asked for."""

    def __init__(self, pages: dict[str, fetch.Page]) -> None:
        """Keep the page table."""
        self.pages = pages
        self.urls: list[str] = []

    def __call__(self, url: str, deadline: float) -> fetch.Page:
        """Return the page for the URL, or fail like an HTTP 404."""
        del deadline
        self.urls.append(url)
        page = self.pages.get(url)
        if page is None:
            msg = "HTTP 404 Not Found"
            raise fetch.FetchError(msg)
        return page


class FakeRender:
    """Render every PDF as one of a fixed number of pages and record the calls."""

    def __init__(self, pages: int = 1) -> None:
        """Keep the page count every document has."""
        self.pages = pages
        self.calls: list[tuple[bytes, int]] = []
        self.until: list[float] = []

    def __call__(self, data: bytes, pageno: int, until: float) -> pdf.Image:
        """Return a stand-in image naming the page, or fail past the last page."""
        self.calls.append((data, pageno))
        self.until.append(until)
        if pageno >= self.pages:
            msg = f"page {pageno} is past the last page; the PDF has {self.pages} pages"
            raise pdf.RenderError(msg)
        return pdf.Image("image/png", b"page %d of %b" % (pageno, data))


def shot(data: bytes, pageno: int) -> dict[str, object]:
    """Return the content item FakeRender's image of the page becomes."""
    image = pdf.Image("image/png", b"page %d of %b" % (pageno, data))
    return {"type": "input_image", "image_url": image.data_url()}


class Emulator:
    """A state directory with a fake search, fetcher, and PDF renderer."""

    def __init__(
        self, directory: Path, hits: list[Hit] | Exception, pages: dict[str, fetch.Page]
    ) -> None:
        """Use the directory for state and the fakes for the network."""
        self.directory = directory
        self.search = FakeSearch(hits)
        self.fetch = FakeFetch(pages)
        self.render = FakeRender()
        self.images = True
        self.logged: list[str] = []

    def seed(self, turn: int, refs: dict[str, webrun.Ref]) -> None:
        """Write a state as if earlier turns had run."""
        state = webrun.State(turn, refs)
        self.directory.mkdir(parents=True, exist_ok=True)
        path = self.directory / f"{webrun.state_name(SESSION)}.json"
        path.write_text(state.dump(), encoding="utf-8")

    def call(self, commands: dict[str, object], **extra: object) -> dict[str, object]:
        """Answer one request with the given commands."""
        request: dict[str, object] = {"id": SESSION, "model": "gpt", "commands": commands}
        return webrun.handle(
            request | extra,
            search=self.search,
            fetch=self.fetch,
            render=self.render,
            images=self.images,
            directory=self.directory,
            now=lambda: NOW,
            log=self.logged.append,
        )


def output(response: dict[str, object]) -> str:
    """Return the response's output text."""
    return cast("str", response["output"])


def ref_ids(response: dict[str, object]) -> list[object]:
    """Return the ref_id of every results entry."""
    return [entry["ref_id"] for entry in cast("list[dict[str, object]]", response["results"])]


class WebRunTestCase(unittest.TestCase):
    """A fresh state directory per test."""

    @override
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.directory = self.root / "kagi-search" / "web-run"

    def emulator(
        self,
        hits: list[Hit] | Exception | None = None,
        pages: dict[str, fetch.Page] | None = None,
    ) -> Emulator:
        """Return an emulator over this test's state directory."""
        return Emulator(self.directory, [] if hits is None else hits, pages or {})


class SearchTest(WebRunTestCase):
    """search_query output, results, and Kagi parameters."""

    def test_search_output_matches_the_capture(self) -> None:
        """Hits read like the captured service output, minus its crawl dates."""
        emulator = self.emulator(GUIX_HITS)
        emulator.seed(4, {})
        response = emulator.call({"search_query": [{"q": "Guix functional package manager"}]})
        self.assertIsNone(response["encrypted_output"])
        self.assertEqual(
            output(response),
            "guix - MyNixOS (https://mynixos.com/nixpkgs/package/guix)\n"
            "\ue200cite\ue202turn4search0\ue201 [wordlim: 200] GNU Guix is a purely functional "
            "package manager for the GNU system, and a distribution thereof.\n"
            + SEPARATOR
            + "GNU Guix - Meta Package Manager (https://mpm.run/managers/guix/)\n"
            "\ue200cite\ue202turn4search1\ue201 [wordlim: 200] GNU Guix, GNU\u2019s functional "
            "package manager.\n",
        )
        self.assertEqual(
            response["results"],
            [
                {
                    "type": "text_result",
                    "domain": "mynixos.com",
                    "ref_id": "turn4search0",
                    "snippet": "GNU Guix is a purely functional package manager for the GNU "
                    "system, and a distribution thereof.",
                    "title": "guix - MyNixOS",
                    "url": "https://mynixos.com/nixpkgs/package/guix",
                },
                {
                    "type": "text_result",
                    "domain": "mpm.run",
                    "ref_id": "turn4search1",
                    "snippet": "GNU Guix, GNU\u2019s functional package manager.",
                    "title": "GNU Guix - Meta Package Manager",
                    "url": "https://mpm.run/managers/guix/",
                },
            ],
        )

    def test_queries_number_hits_across_the_call(self) -> None:
        """Two queries share one search counter."""
        emulator = self.emulator(GUIX_HITS)
        response = emulator.call({"search_query": [{"q": "a"}, {"q": "b"}]})
        self.assertEqual(
            ref_ids(response), ["turn0search0", "turn0search1", "turn0search2", "turn0search3"]
        )
        self.assertEqual(output(response).count(SEPARATOR), 3)

    def test_kagi_parameters(self) -> None:
        """Length sets the limit, domains narrow the query, and settings filter it."""
        emulator = self.emulator(GUIX_HITS)
        emulator.call({"search_query": [{"q": "a"}]})
        emulator.call(
            {"search_query": [{"q": "b", "domains": ["x.org"]}], "response_length": "long"}
        )
        emulator.call(
            {"search_query": [{"q": "c"}], "response_length": "medium"},
            settings={"filters": {"allowed_domains": ["y.org"], "blocked_domains": ["z.org"]}},
        )
        self.assertEqual(
            emulator.search.calls,
            [
                ("a", None, None, webrun.HITS_PER_LENGTH["short"]),
                ("b", ["x.org"], None, webrun.HITS_PER_LENGTH["long"]),
                ("c", ["y.org"], ["z.org"], webrun.HITS_PER_LENGTH["medium"]),
            ],
        )

    def test_query_domains_narrow_the_allowed_domains(self) -> None:
        """A hit must match the configured allowlist and the query's domains, minus blocks."""
        hits = [
            Hit("Root", "https://nixos.org/", ""),
            Hit("Wiki", "https://wiki.nixos.org/wiki/Flakes", ""),
            Hit("Old", "https://old.wiki.nixos.org/x", ""),
            Hit("Elsewhere", "https://example.com/", ""),
        ]
        emulator = self.emulator(hits)
        response = emulator.call(
            {"search_query": [{"q": "a", "domains": ["wiki.nixos.org", "example.com"]}]},
            settings={
                "filters": {
                    "allowed_domains": ["nixos.org"],
                    "blocked_domains": ["old.wiki.nixos.org"],
                }
            },
        )
        self.assertEqual(emulator.search.calls[0][1], ["wiki.nixos.org"])
        urls = [
            cast("dict[str, object]", r)["url"] for r in cast("list[object]", response["results"])
        ]
        self.assertEqual(urls, ["https://wiki.nixos.org/wiki/Flakes"])

    def test_allowed_domains(self) -> None:
        """Each pair keeps its narrower domain; one list alone passes through."""
        self.assertEqual(
            webrun.allowed_domains(["wiki.nixos.org"], ["nixos.org"]), ["wiki.nixos.org"]
        )
        self.assertEqual(
            webrun.allowed_domains(["nixos.org"], ["wiki.nixos.org"]), ["wiki.nixos.org"]
        )
        self.assertEqual(webrun.allowed_domains(["nixos.org"], ["notnixos.org"]), [])
        self.assertEqual(webrun.allowed_domains(None, ["https://A.org/x"]), ["a.org"])
        self.assertEqual(webrun.allowed_domains(["a.org"], None), ["a.org"])
        self.assertIsNone(webrun.allowed_domains(None, []))

    def test_disjoint_domains_skip_kagi(self) -> None:
        """A query whose domains all fall outside the allowlist searches and finds nothing."""
        emulator = self.emulator(GUIX_HITS)
        response = emulator.call(
            {"search_query": [{"q": "a", "domains": ["example.com"]}]},
            settings={"filters": {"allowed_domains": ["nixos.org"]}},
        )
        self.assertEqual(emulator.search.calls, [])
        self.assertEqual(output(response), webrun.EMPTY_SEARCH)
        self.assertEqual(response["results"], [])

    def test_recency_becomes_a_start_date(self) -> None:
        """A recency of N days asks Kagi for pages from N days before today, none for none."""
        emulator = self.emulator(GUIX_HITS)
        emulator.call({"search_query": [{"q": "a", "recency": 7}, {"q": "b"}]})
        self.assertEqual(emulator.search.since, [dt.date(2026, 11, 1), None])

    def test_a_search_ends_by_the_calls_deadline(self) -> None:
        """Each search is handed the call's deadline, so one started late cannot outlast it."""
        emulator = self.emulator(GUIX_HITS)
        started = time.monotonic()
        emulator.call({"search_query": [{"q": "a"}]})
        (until,) = emulator.search.until
        self.assertGreaterEqual(until, started + webrun.CALL_DEADLINE_SECONDS)
        self.assertLessEqual(until, time.monotonic() + webrun.CALL_DEADLINE_SECONDS)

    def test_empty_and_fruitless_queries(self) -> None:
        """An empty query skips Kagi; queries without hits give the service's empty answer."""
        emulator = self.emulator([])
        response = emulator.call({"search_query": [{"q": ""}, {"q": "zzz"}]})
        self.assertEqual(output(response), webrun.EMPTY_SEARCH)
        self.assertEqual([call[0] for call in emulator.search.calls], ["zzz"])


class ViewTest(WebRunTestCase):
    """open, click, and find."""

    def lix(self) -> Emulator:
        """Return an emulator whose state matches the capture before its open call."""
        emulator = self.emulator(
            GUIX_HITS,
            {
                LIX_URL: html(LIX_URL, LIX_HTML),
                MANUAL_URL: html(MANUAL_URL, MANUAL_HTML),
                "https://lix.systems/install/": html(
                    "https://lix.systems/install/", "<title>Install</title><p>curl | sh</p>"
                ),
            },
        )
        emulator.seed(1, {"turn0search0": webrun.Ref(LIX_URL, LIX_TITLE)})
        return emulator

    def test_open_matches_the_capture(self) -> None:
        """An opened page reads like the captured view, link markers included."""
        response = self.lix().call({"open": [{"ref_id": "turn0search0"}]})
        self.assertEqual(
            output(response),
            f"{LIX_TITLE} ({LIX_URL})\n"
            "\ue200cite\ue202turn1view0\ue201 [wordlim: 200] Crawled: today; Content type: "
            'text/html; Source: open({"ref_id":"turn0search0","lineno":null}); Total lines: 18\n'
            + "".join(f"{line}\n" for line in LIX_LINES),
        )
        self.assertEqual(
            response["results"],
            [
                {
                    "type": "text_result",
                    "domain": "lix.systems",
                    "ref_id": "turn1view0",
                    "snippet": "Total lines: 18",
                    "title": LIX_TITLE,
                    "url": LIX_URL,
                }
            ],
        )

    def test_click_follows_the_stored_link_table(self) -> None:
        """Link 2 of the opened page is the install page, numbered once for two anchors."""
        emulator = self.lix()
        emulator.call({"open": [{"ref_id": "turn0search0"}]})
        response = emulator.call({"click": [{"ref_id": "turn1view0", "id": 2}]})
        self.assertEqual(emulator.fetch.urls[-1], "https://lix.systems/install/")
        self.assertEqual(
            output(response),
            "Install (https://lix.systems/install/)\n"
            "\ue200cite\ue202turn2view0\ue201 [wordlim: 200] Crawled: today; Content type: "
            'text/html; Source: click({"ref_id":"turn1view0","id":2}); Total lines: 1\n'
            "L0: curl | sh\n",
        )

    def test_click_on_a_missing_link_is_an_invalid_call(self) -> None:
        """A link id past the table gets the service's invalid-arguments block."""
        emulator = self.lix()
        emulator.call({"open": [{"ref_id": "turn0search0"}]})
        response = emulator.call({"click": [{"ref_id": "turn1view0", "id": 40}]})
        message = "Unable to resolve click call due to invalid arguments"
        self.assertEqual(
            output(response),
            "Internal Error ()\n\ue200cite\ue202turn2view0\ue201 [wordlim: 200] "
            f"{message}\nL0: {message}\n",
        )
        self.assertEqual(
            response["results"],
            [
                {
                    "type": "text_result",
                    "ref_id": "turn2view0",
                    "snippet": message,
                    "title": "Internal Error",
                }
            ],
        )

    def test_find_without_match_matches_the_capture(self) -> None:
        """No match prints the service's one line under the view header."""
        emulator = self.lix()
        emulator.seed(3, {"turn2view0": webrun.Ref(MANUAL_URL, MANUAL_TITLE, [])})
        response = emulator.call({"find": [{"ref_id": "turn2view0", "pattern": "release"}]})
        self.assertEqual(
            output(response),
            f"{MANUAL_TITLE} ({MANUAL_URL})\n"
            "\ue200cite\ue202turn3view0\ue201 [wordlim: 200] Crawled: today; Content type: "
            'text/html; Source: find({"ref_id":"turn2view0","pattern":"release"}); Total lines: 3\n'
            'No matching text found for "release"',
        )

    def test_find_shows_matches_with_context(self) -> None:
        """Matches are case-insensitive and come with two lines either side."""
        response = self.lix().call({"find": [{"ref_id": "turn0search0", "pattern": "BINGSU"}]})
        body = output(response).split("\n", 2)[2]
        self.assertEqual(body, "".join(f"{line}\n" for line in LIX_LINES[:11]))

    def test_open_and_find_in_one_call(self) -> None:
        """Views share one counter and the blocks are dash-separated, as captured."""
        response = self.lix().call(
            {
                "open": [{"ref_id": "turn0search0"}],
                "find": [{"ref_id": "turn0search0", "pattern": "Scheme"}],
            }
        )
        first, second = output(response).split(SEPARATOR)
        self.assertIn("\ue202turn1view0\ue201", first)
        self.assertTrue(first.endswith(LIX_LINES[17] + "\n"))
        self.assertIn("\ue202turn1view1\ue201", second)
        self.assertTrue(second.endswith('No matching text found for "Scheme"'))
        self.assertEqual(ref_ids(response), ["turn1view0", "turn1view1"])

    def test_turns_count_calls_and_views_find_their_page(self) -> None:
        """Every call takes the next turn; a view's ref opens its page again."""
        emulator = self.lix()
        emulator.call({"time": [{"utc_offset": "+00:00"}]})
        response = emulator.call({"open": [{"ref_id": "turn0search0"}]})
        self.assertIn("\ue202turn2view0\ue201", output(response))
        response = emulator.call({"open": [{"ref_id": "turn2view0", "lineno": 4}]})
        self.assertIn("\ue202turn3view0\ue201", output(response))
        self.assertIn('open({"ref_id":"turn2view0","lineno":4})', output(response))

    def test_a_literal_url_opens(self) -> None:
        """A URL as ref_id opens directly and a redirect is named in the header."""
        moved = html(LIX_URL, LIX_HTML, redirected=True)
        emulator = self.emulator(pages={"https://lix.systems/old": moved})
        response = emulator.call({"open": [{"ref_id": "https://lix.systems/old"}]})
        header = output(response).split("\n")[1]
        self.assertIn(f"Redirected to URL: {LIX_URL}; Total lines: 18", header)

    def test_failed_fetches_are_not_accessible(self) -> None:
        """A page that cannot be fetched gets the service's not-accessible block; others run."""
        emulator = self.lix()
        response = emulator.call(
            {"open": [{"ref_id": "https://example.org/gone"}, {"ref_id": "turn0search0"}]}
        )
        first, second = output(response).split(SEPARATOR)
        self.assertEqual(
            first,
            "Internal Error ()\n\ue200cite\ue202turn1view0\ue201 [wordlim: 200] Source: "
            'open({"ref_id":"https://example.org/gone","lineno":null}); \n'
            "URL https://example.org/gone is not accessible via this tool.",
        )
        self.assertIn("\ue202turn1view1\ue201", second)
        self.assertEqual(
            cast("list[object]", response["results"])[0],
            {"type": "text_result", "ref_id": "turn1view0", "title": "Internal Error"},
        )
        self.assertTrue(any("HTTP 404 Not Found" in line for line in emulator.logged))

    def test_plain_text_and_unshowable_types(self) -> None:
        """Plain text keeps its lines, a PDF is not accessible, an image has no readable lines."""
        emulator = self.emulator(
            pages={
                "https://x.org/a.txt": fetch.Page(
                    "https://x.org/a.txt", "text/plain", "a\n\nb", redirected=False
                ),
                "https://x.org/a.pdf": fetch.Page(
                    "https://x.org/a.pdf", "application/pdf", None, redirected=False
                ),
                "https://x.org/a.png": fetch.Page(
                    "https://x.org/a.png", "image/png", None, redirected=False
                ),
            }
        )
        response = emulator.call(
            {
                "open": [
                    {"ref_id": "https://x.org/a.txt"},
                    {"ref_id": "https://x.org/a.pdf"},
                    {"ref_id": "https://x.org/a.png"},
                ]
            }
        )
        text, pdf, png = output(response).split(SEPARATOR)
        self.assertTrue(text.endswith("Total lines: 3\nL0: a\nL1: \nL2: b\n"))
        self.assertTrue(pdf.endswith("URL https://x.org/a.pdf is not accessible via this tool."))
        self.assertEqual(
            png,
            " (https://x.org/a.png)\n\ue200cite\ue202turn0view2\ue201 "
            "This page has no readable lines.",
        )
        self.assertEqual(ref_ids(response), ["turn0view0", "turn0view1"])


PDF_URL = "https://x.org/paper.pdf"
PDF_BYTES = b"%PDF-1.4 stand-in"
CITE_VIEW = "\ue200cite\ue202turn0view{}\ue201"


class ScreenshotTest(WebRunTestCase):
    """PDF pages returned as images beside the service's own screenshot block."""

    def pdf_emulator(self, pages: int = 3) -> Emulator:
        """Return an emulator serving one PDF of that many pages and an HTML page."""
        emulator = self.emulator(
            pages={
                PDF_URL: fetch.Page(
                    PDF_URL, "application/pdf", None, redirected=False, data=PDF_BYTES
                ),
                "https://x.org/": html("https://x.org/", "<title>X</title><p>hello</p>"),
            }
        )
        emulator.render = FakeRender(pages)
        return emulator

    def test_a_page_image_follows_its_block(self) -> None:
        """The block reads as the service's, and content carries its text and the image."""
        emulator = self.pdf_emulator()
        response = emulator.call({"screenshot": [{"ref_id": PDF_URL, "pageno": 2}]})
        block = f" ({PDF_URL})\n{CITE_VIEW.format(0)} "
        self.assertEqual(output(response), block)
        self.assertEqual(response["results"], [])
        self.assertEqual(
            response["content"], [{"type": "input_text", "text": block}, shot(PDF_BYTES, 2)]
        )
        self.assertEqual(emulator.render.calls, [(PDF_BYTES, 2)])
        self.assertEqual(emulator.logged, [])

    def test_images_sit_between_the_blocks_they_belong_to(self) -> None:
        """Each image comes right after its block's text, and the text items join to the output."""
        emulator = self.pdf_emulator()
        response = emulator.call(
            {
                "open": [{"ref_id": "https://x.org/"}],
                "screenshot": [
                    {"ref_id": PDF_URL, "pageno": 0},
                    {"ref_id": PDF_URL, "pageno": 9},
                    {"ref_id": PDF_URL, "pageno": 1},
                ],
                "time": [{"utc_offset": "+00:00"}],
            }
        )
        content = cast("list[dict[str, str]]", response["content"])
        self.assertEqual(
            [item["type"] for item in content],
            ["input_text", "input_image", "input_text", "input_image", "input_text"],
        )
        self.assertEqual([content[1], content[3]], [shot(PDF_BYTES, 0), shot(PDF_BYTES, 1)])
        texts = [item["text"] for item in content if item["type"] == "input_text"]
        self.assertEqual("".join(texts), output(response))
        self.assertTrue(texts[0].endswith(f" ({PDF_URL})\n{CITE_VIEW.format(1)} "))
        self.assertTrue(texts[1].endswith(f" ({PDF_URL})\n{CITE_VIEW.format(3)} "))
        self.assertIn(f"Failed to fetch {PDF_URL}: Internal Error", texts[1])
        self.assertTrue(texts[2].startswith(SEPARATOR + "\ue200cite\ue202turn0time0\ue201"))
        self.assertEqual(emulator.fetch.urls, ["https://x.org/", PDF_URL])

    def test_a_page_that_cannot_be_rendered_fails_as_the_service_does(self) -> None:
        """A page past the last one answers with the service's failure; the log has the reason."""
        emulator = self.pdf_emulator(pages=3)
        response = emulator.call({"screenshot": [{"ref_id": PDF_URL, "pageno": 3}]})
        self.assertEqual(
            output(response),
            f"Internal Error ()\n{CITE_VIEW.format(0)} [wordlim: 200] Source: "
            f'screenshot({{"ref_id":"{PDF_URL}","pageno":3,"height":null,"offset":null}}); \n'
            f"Failed to fetch {PDF_URL}: Internal Error",
        )
        self.assertEqual(
            response["results"],
            [{"type": "text_result", "ref_id": "turn0view0", "title": "Internal Error"}],
        )
        self.assertNotIn("content", response)
        self.assertEqual(len(emulator.logged), 1)
        self.assertIn(f"no image of {PDF_URL}: page 3 is past the last page", emulator.logged[0])

    def test_no_image_is_claimed_when_codex_takes_none(self) -> None:
        """Without Codex's image support a screenshot fails; nothing is rendered."""
        emulator = self.pdf_emulator()
        emulator.images = False
        response = emulator.call({"screenshot": [{"ref_id": PDF_URL, "pageno": 0}]})
        self.assertTrue(output(response).endswith(f"Failed to fetch {PDF_URL}: Internal Error"))
        self.assertEqual(ref_ids(response), ["turn0view0"])
        self.assertNotIn("content", response)
        self.assertEqual(emulator.render.calls, [])
        self.assertIn("CODEX_WEB_RUN_IMAGES is not 1", emulator.logged[0])

    def test_an_image_cut_by_the_budget_is_left_out(self) -> None:
        """A screenshot block past the output budget takes its image with it."""
        emulator = self.pdf_emulator()
        response = emulator.call(
            {
                "open": [{"ref_id": "https://x.org/"}],
                "screenshot": [{"ref_id": PDF_URL, "pageno": 0}],
            },
            max_output_tokens=60,
        )
        self.assertIn("L0: hello", output(response))
        self.assertNotIn(PDF_URL, output(response))
        self.assertNotIn("content", response)
        self.assertTrue(any("an image is left out" in line for line in emulator.logged))
        emulator.logged.clear()
        cut = emulator.call({"screenshot": [{"ref_id": PDF_URL, "pageno": 0}]}, max_output_tokens=8)
        self.assertEqual(output(cut), f" ({PDF_URL})\n")
        self.assertNotIn("content", cut)
        self.assertTrue(any("an image is left out" in line for line in emulator.logged))

    def test_a_call_stops_adding_images_at_its_byte_limit(self) -> None:
        """Past the call's image budget a screenshot fails; the images before it stay."""
        emulator = self.pdf_emulator()
        one = len(pdf.Image("image/png", b"page 0 of " + PDF_BYTES).data)
        with unittest.mock.patch.object(webrun, "MAX_CALL_IMAGE_BYTES", 2 * one):
            response = emulator.call(
                {"screenshot": [{"ref_id": PDF_URL, "pageno": page} for page in (0, 1, 2)]}
            )
        content = cast("list[dict[str, str]]", response["content"])
        images = [item for item in content if item["type"] == "input_image"]
        self.assertEqual(images, [shot(PDF_BYTES, 0), shot(PDF_BYTES, 1)])
        self.assertTrue(output(response).endswith(f"Failed to fetch {PDF_URL}: Internal Error"))
        self.assertIn("the call's images would pass", emulator.logged[0])

    def test_only_recent_pdfs_stay_in_memory(self) -> None:
        """PDFs past the kept-bytes limit are forgotten and fetched again when asked for."""
        emulator = self.pdf_emulator()
        other = "https://x.org/other.pdf"
        emulator.fetch.pages[other] = fetch.Page(
            other, "application/pdf", None, redirected=False, data=PDF_BYTES
        )
        shots = [{"ref_id": url, "pageno": 0} for url in (PDF_URL, PDF_URL, other, PDF_URL)]
        with unittest.mock.patch.object(webrun, "MAX_KEPT_PDF_BYTES", len(PDF_BYTES)):
            response = emulator.call({"screenshot": shots})
        self.assertEqual(emulator.fetch.urls, [PDF_URL, other, PDF_URL])
        content = cast("list[dict[str, str]]", response["content"])
        self.assertEqual(sum(item["type"] == "input_image" for item in content), len(shots))

    def test_rendering_ends_before_the_call_deadline(self) -> None:
        """The renderer is given the call's deadline less the margin that leaves time to answer."""
        emulator = self.pdf_emulator()
        started = time.monotonic()
        emulator.call({"screenshot": [{"ref_id": PDF_URL, "pageno": 0}]})
        limit = webrun.CALL_DEADLINE_SECONDS - webrun.PAGE_START_MARGIN_SECONDS
        self.assertLessEqual(emulator.render.until[0], time.monotonic() + limit)
        self.assertGreaterEqual(emulator.render.until[0], started + limit)

    def test_a_response_without_images_has_no_content(self) -> None:
        """Only a response with an image carries content items."""
        response = self.pdf_emulator().call({"open": [{"ref_id": "https://x.org/"}]})
        self.assertNotIn("content", response)


class WindowTest(WebRunTestCase):
    """lineno positioning and truncation to the output budget."""

    def long_page(self) -> Emulator:
        """Return an emulator serving a 1000-line page."""
        body = "".join(f"<p>line {index} {'x' * 40}</p>" for index in range(1000))
        return self.emulator(pages={"https://x.org/": html("https://x.org/", body)})

    @staticmethod
    def numbers(text: str) -> list[int]:
        """Return the line numbers shown."""
        return [int(line[1:].split(":", 1)[0]) for line in text.splitlines() if line[:1] == "L"]

    def test_truncation_has_no_marker(self) -> None:
        """A long page stops at the budget, keeps its total, and adds nothing."""
        response = self.long_page().call(
            {"open": [{"ref_id": "https://x.org/"}]}, max_output_tokens=1000
        )
        text = output(response)
        shown = self.numbers(text)
        self.assertEqual(shown[0], 0)
        self.assertLess(shown[-1], 1998)
        self.assertEqual(shown, list(range(shown[-1] + 1)))
        self.assertLessEqual(len(text), 1000 * webrun.CHARS_PER_TOKEN)
        self.assertIn("Total lines: 1999", text)
        self.assertTrue(text.endswith("\n"))
        self.assertNotIn("truncated", text.lower())
        self.assertNotIn("\u2026", text)

    def test_lineno_positions_the_window(self) -> None:
        """The window starts at lineno and backs up only when the page ends first."""
        emulator = self.long_page()
        middle = self.numbers(
            output(
                emulator.call(
                    {"open": [{"ref_id": "https://x.org/", "lineno": 500}]}, max_output_tokens=1000
                )
            )
        )
        self.assertEqual(middle[0], 500)
        end = self.numbers(
            output(
                emulator.call(
                    {"open": [{"ref_id": "https://x.org/", "lineno": 5000}]}, max_output_tokens=1000
                )
            )
        )
        self.assertEqual(end[-1], 1998)
        self.assertLess(end[0], 1998 - 10)

    def test_window_function(self) -> None:
        """The window fills forward, then backward once the page ends."""
        lines = ["abc"] * 10
        size = len("L0: abc\n")
        self.assertEqual(webrun.window(lines, 2, size * 3), range(2, 5))
        self.assertEqual(webrun.window(lines, 9, size * 3), range(7, 10))
        self.assertEqual(webrun.window(lines, 0, 10_000), range(10))
        self.assertEqual(webrun.window([], 3, 100), range(0))


class LongLineTest(WebRunTestCase):
    """A single-line document stays reachable to lineno and find."""

    def emulate(self) -> tuple[Emulator, list[str]]:
        """Return an emulator serving one 30,000-character line ending in a needle."""
        words = [f"word{index:05d}" for index in range(3000)] + ["needle"]
        body = " ".join(words)
        page = fetch.Page("https://x.org/one.txt", "text/plain", body, redirected=False)
        return self.emulator(pages={"https://x.org/one.txt": page}), words

    def test_segments_are_numbered_and_stable(self) -> None:
        """The line splits into numbered segments, the same on every call."""
        emulator, words = self.emulate()
        first = output(emulator.call({"open": [{"ref_id": "https://x.org/one.txt"}]}))
        again = output(emulator.call({"open": [{"ref_id": "https://x.org/one.txt"}]}))
        total = int(first.split("Total lines: ", 1)[1].split("\n", 1)[0])
        self.assertGreater(total, 20)
        self.assertEqual(first.split("\n", 2)[2], again.split("\n", 2)[2])
        shown = " ".join(line.split(": ", 1)[1] for line in first.splitlines()[2:])
        self.assertTrue(" ".join(words).startswith(shown))

    def test_lineno_and_find_reach_the_end(self) -> None:
        """Past the output budget, the last segment opens by lineno and find lands on it."""
        emulator, _ = self.emulate()
        found = output(
            emulator.call(
                {"find": [{"ref_id": "https://x.org/one.txt", "pattern": "NEEDLE"}]},
                max_output_tokens=SMALL_TOKENS,
            )
        )
        total = int(found.split("Total lines: ", 1)[1].split("\n", 1)[0])
        last = f"L{total - 1}: "
        self.assertIn(last, found)
        self.assertTrue(found.rstrip("\n").endswith(" needle"))
        opened = output(
            emulator.call(
                {"open": [{"ref_id": "https://x.org/one.txt", "lineno": total - 1}]},
                max_output_tokens=SMALL_TOKENS,
            )
        )
        self.assertTrue(opened.rstrip("\n").endswith(" needle"))


class BudgetTest(WebRunTestCase):
    """The whole output fits the character budget max_output_tokens implies."""

    def test_many_opens_fit_a_small_budget(self) -> None:
        """Five long pages under 1000 tokens stay within 4000 characters; results stay whole."""
        body = "".join(f"<p>Paragraph {i} {'lorem ipsum ' * 12}</p>" for i in range(400))
        pages = {f"https://s{i}.org/": html(f"https://s{i}.org/", body) for i in range(5)}
        response = self.emulator(pages=pages).call(
            {"open": [{"ref_id": url} for url in pages], "time": [{"utc_offset": "+00:00"}]},
            max_output_tokens=1000,
        )
        text = output(response)
        self.assertLessEqual(len(text), 1000 * webrun.CHARS_PER_TOKEN)
        self.assertEqual(len(ref_ids(response)), 5)
        self.assertIn("\ue202turn0view0\ue201", text)
        self.assertNotIn("omitted", text)

    def test_many_hits_fit_and_drop_the_rest_silently(self) -> None:
        """Hits past the budget are dropped without a note; results keep all of them."""
        hits = [Hit(f"Hit {i}", f"https://h{i}.org/", "x" * 200) for i in range(30)]
        response = self.emulator(hits).call(
            {"search_query": [{"q": f"q{i}"} for i in range(5)]}, max_output_tokens=2000
        )
        text = output(response)
        self.assertLessEqual(len(text), 2000 * webrun.CHARS_PER_TOKEN)
        self.assertEqual(len(ref_ids(response)), 150)
        self.assertLess(text.count("\ue200cite"), 150)
        self.assertTrue(text.endswith("\n"))

    def test_fit_blocks_never_exceeds_the_budget(self) -> None:
        """For any budget the joined blocks fit and are a prefix of the whole output."""
        blocks = [f"Hit {i} (https://x/{i})\nCITE " + "x" * 200 + "\n" for i in range(40)]
        full = webrun.join_blocks(blocks)
        for budget in range(0, len(full) + 200, 37):
            with self.subTest(budget=budget):
                text = webrun.fit_blocks(blocks, budget)
                self.assertLessEqual(len(text), budget)
                self.assertTrue(full.startswith(text))


class OtherCommandsTest(WebRunTestCase):
    """time and the commands Kagi cannot answer."""

    def test_time(self) -> None:
        """Offsets give the service's time sentence; a malformed one is left out."""
        response = self.emulator().call(
            {"time": [{"utc_offset": "+03:00"}, {"utc_offset": "-05:30"}, {"utc_offset": "soon"}]}
        )
        self.assertEqual(
            output(response),
            "\ue200cite\ue202turn0time0\ue201 The time in UTC+03:00 is Nov 8, 2026, 3:00:00\u202fPM"
            + SEPARATOR
            + "\ue200cite\ue202turn0time1\ue201 "
            "The time in UTC-05:30 is Nov 8, 2026, 6:30:00\u202fAM",
        )

    def test_unserved_commands(self) -> None:
        """Commands Kagi cannot answer are left out like invalid items; alone, nothing answers."""
        commands: dict[str, object] = {
            "literature_search_query": [{"q": "x"}],
            "image_query": [{"q": "x"}],
            "finance": [{"ticker": "AMD", "type": "equity", "market": "USA"}],
            "weather": [{"location": "Prague"}],
            "sports": [{"tool": "sports", "fn": "standings", "league": "nfl"}],
        }
        emulator = self.emulator()
        response = emulator.call(commands)
        self.assertEqual(output(response), webrun.NO_TOOL_RESPONSE)
        self.assertEqual(response["results"], [])
        self.assertIsNone(response["encrypted_output"])
        batched = emulator.call({**commands, "time": [{"utc_offset": "+00:00"}]})
        self.assertTrue(output(batched).startswith("\ue200cite\ue202turn1time0\ue201 The time"))


class StateTest(WebRunTestCase):
    """The per-session state file."""

    def test_permissions_and_name(self) -> None:
        """Directory 0700 and files 0600 under a permissive umask; the name stays inside."""
        self.directory.parent.mkdir(mode=0o755)
        old = os.umask(0)
        try:
            emulator = self.emulator()
            request: dict[str, object] = {"id": "../../etc/passwd", "commands": {}}
            webrun.handle(
                request,
                search=emulator.search,
                fetch=emulator.fetch,
                render=emulator.render,
                images=emulator.images,
                directory=self.directory,
                now=lambda: NOW,
                log=emulator.logged.append,
            )
        finally:
            os.umask(old)
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.directory.parent.stat().st_mode), 0o700)
        files = sorted(self.directory.iterdir())
        self.assertEqual(len(files), 2)
        for path in files:
            self.assertEqual(path.parent, self.directory)
            self.assertTrue(path.name.startswith("______etc_passwd-"))
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_distinct_sessions_have_distinct_files(self) -> None:
        """Ids that sanitize alike still get separate files."""
        self.assertNotEqual(webrun.state_name("a/b"), webrun.state_name("a_b"))

    def test_concurrent_calls_take_distinct_turns(self) -> None:
        """The lock keeps parallel calls of one session from sharing a turn."""
        session = webrun.Session(self.directory, SESSION)
        turns: list[int] = []

        def begin() -> None:
            turns.append(session.begin()[0])

        threads = [threading.Thread(target=begin) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(sorted(turns), list(range(8)))

    def test_refs_merge_across_calls(self) -> None:
        """Recording adds to what is stored rather than replacing it."""
        session = webrun.Session(self.directory, SESSION)
        session.begin()
        session.record({"turn0search0": webrun.Ref("https://a.org/", "A")})
        session.record({"turn1view0": webrun.Ref("https://b.org/", "B", ["https://c.org/"])})
        turn, refs = session.begin()
        self.assertEqual(turn, 1)
        self.assertEqual(
            refs,
            {
                "turn0search0": webrun.Ref("https://a.org/", "A"),
                "turn1view0": webrun.Ref("https://b.org/", "B", ["https://c.org/"]),
            },
        )

    def test_corrupt_state_is_an_error(self) -> None:
        """An unreadable state file fails the call instead of restarting at turn 0."""
        self.directory.mkdir(parents=True)
        (self.directory / f"{webrun.state_name(SESSION)}.json").write_text("{", encoding="utf-8")
        with self.assertRaisesRegex(webrun.StateError, "delete it to reset"):
            self.emulator().call({})

    def age(self, name: str, days: float) -> Path:
        """Create the file in the state directory, last written days before NOW."""
        path = self.directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{}", encoding="utf-8")
        when = (NOW - dt.timedelta(days=days)).timestamp()
        os.utime(path, (when, when))
        return path

    def test_prune_removes_only_stale_other_sessions(self) -> None:
        """State unwritten for 30 days goes with its lock; current, busy, and fresh stay."""
        mine = webrun.state_name(SESSION)
        kept = [
            self.age(f"{mine}.json", 90),
            self.age(f"{mine}.lock", 90),
            self.age("fresh.json", 29),
            self.age("fresh.lock", 90),
            self.age("young-orphan.lock", 29),
            self.age("busy.json", 31),
            self.age("busy.lock", 31),
            self.age("notes.txt", 90),
            self.age(".fresh.json.x.tmp", 1),
        ]
        gone = [
            self.age("old.json", 31),
            self.age("old.lock", 31),
            self.age("lockless.json", 31),
            self.age("orphan.lock", 31),
            self.age(".old.json.x.tmp", 31),
        ]
        with (self.directory / "busy.lock").open("rb") as busy:
            fcntl.flock(busy.fileno(), fcntl.LOCK_EX)
            webrun.Session(self.directory, SESSION).prune(NOW)
        self.assertEqual(sorted(self.directory.iterdir()), sorted(kept))
        self.assertTrue(all(not path.exists() for path in gone))
        self.assertFalse((self.directory / "lockless.lock").exists())

    def test_prune_rechecks_age_under_the_lock(self) -> None:
        """State rewritten while pruning waits for its lock survives."""
        state = self.age("racy.json", 31)
        lock = self.age("racy.lock", 31)
        original = webrun.fcntl.flock

        def flock(descriptor: int, operation: int) -> None:
            original(descriptor, operation)
            if os.fstat(descriptor).st_ino == lock.stat().st_ino:
                os.utime(state, (NOW.timestamp(), NOW.timestamp()))

        with unittest.mock.patch.object(webrun.fcntl, "flock", flock):
            webrun.Session(self.directory, SESSION).prune(NOW)
        self.assertTrue(state.exists())
        self.assertTrue(lock.exists())

    def test_a_call_prunes_other_sessions(self) -> None:
        """Every call sweeps the stale sessions of others and keeps its own."""
        old = [self.age("old.json", 45), self.age("old.lock", 45)]
        self.emulator().call({})
        self.assertTrue(all(not path.exists() for path in old))
        self.assertTrue((self.directory / f"{webrun.state_name(SESSION)}.json").exists())

    def test_a_pruned_lock_is_not_held(self) -> None:
        """A caller locking a file that pruning unlinked retries on the new file."""
        session = webrun.Session(self.directory, SESSION)
        session.begin()
        replaced = threading.Event()
        original = webrun.fcntl.flock

        def flock(descriptor: int, operation: int) -> None:
            original(descriptor, operation)
            if not replaced.is_set():
                replaced.set()
                session.lock_path.unlink()

        with unittest.mock.patch.object(webrun.fcntl, "flock", flock):
            turn, _ = session.begin()
        self.assertEqual(turn, 1)
        self.assertTrue(session.lock_path.exists())


class UnexpectedErrorTest(WebRunTestCase):
    """A bug in a page operation costs that page only; a search bug fails the call."""

    def test_a_crashing_fetch_is_not_accessible(self) -> None:
        """A crashing fetch answers like an unreachable page and logs its traceback."""

        class CrashingFetch(FakeFetch):
            @override
            def __call__(self, url: str, deadline: float) -> fetch.Page:
                msg = f"boom {url}"
                raise RuntimeError(msg)

        emulator = self.emulator()
        emulator.fetch = CrashingFetch({})
        response = emulator.call(
            {"open": [{"ref_id": "https://x.org/"}], "time": [{"utc_offset": "+00:00"}]}
        )
        first, second = output(response).split(SEPARATOR)
        self.assertTrue(first.endswith("URL https://x.org/ is not accessible via this tool."))
        self.assertTrue(second.startswith("\ue200cite\ue202turn0time0\ue201"))
        self.assertTrue(any("Traceback" in line for line in emulator.logged))

    def test_a_crashing_search_fails_the_call(self) -> None:
        """A search that raises fails the whole call, as a failing service would."""
        with self.assertRaises(ZeroDivisionError):
            self.emulator(ZeroDivisionError("search bug")).call({"search_query": [{"q": "a"}]})


def run_main(request: object, *, state_home: Path) -> tuple[int, str, str]:
    """Run main on the request with Kagi faked away; return code, stdout, stderr."""
    raw = request if isinstance(request, bytes) else json.dumps(request).encode()
    stdin = io.TextIOWrapper(io.BytesIO(raw))
    out, err = io.StringIO(), io.StringIO()
    with (
        unittest.mock.patch.object(webrun.sys, "stdin", stdin),
        unittest.mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}),
        contextlib.redirect_stdout(out),
        contextlib.redirect_stderr(err),
    ):
        code = webrun.main()
    return code, out.getvalue(), err.getvalue()


class MainTest(WebRunTestCase):
    """Exit status, stdout, stderr, and the log of the program."""

    def log_text(self) -> str:
        """Return the log file's text."""
        return (self.root / "kagi-search" / "web-run.log").read_text(encoding="utf-8")

    def assert_unavailable(self, code: int, out: str, err: str) -> None:
        """Assert the call failed exactly as Codex shows the service's HTTP 503."""
        self.assertEqual((code, out, err), (webrun.FAILURE_EXIT, "", webrun.SERVICE_UNAVAILABLE))

    def test_success_prints_one_response(self) -> None:
        """One JSON response goes to stdout, nothing to stderr, and state under XDG_STATE_HOME."""
        with unittest.mock.patch.object(cli, "run", FakeSearch(GUIX_HITS)):
            code, out, err = run_main(
                {"id": SESSION, "model": "m", "commands": {"search_query": [{"q": "guix"}]}},
                state_home=self.root,
            )
        self.assertEqual((code, err), (0, ""))
        response = json.loads(out)
        self.assertIsNone(response["encrypted_output"])
        self.assertEqual(len(response["results"]), 2)
        self.assertTrue(any(self.directory.glob("*.json")))

    def test_a_screenshot_reaches_stdout_as_an_image_when_codex_takes_images(self) -> None:
        """With Codex's CODEX_WEB_RUN_IMAGES=1 the real renderer's page is in content."""
        sandbox.require()
        document = pdfs.document([pdfs.rectangle((1, 0, 0), (0, 0, *pdfs.LETTER))])
        broken = "https://x.org/broken.pdf"
        pages = {
            PDF_URL: fetch.Page(PDF_URL, "application/pdf", None, redirected=False, data=document),
            broken: fetch.Page(broken, "application/pdf", None, redirected=False, data=b"junk"),
        }
        shots = [{"ref_id": broken, "pageno": 0}, {"ref_id": PDF_URL, "pageno": 0}]
        request = {"id": SESSION, "commands": {"screenshot": shots}}
        for value, expected in (("1", True), ("", False), ("0", False)):
            with (
                self.subTest(value=value),
                unittest.mock.patch.object(webrun, "fetch_page", FakeFetch(pages)),
                unittest.mock.patch.dict(os.environ, {webrun.IMAGES_ENV: value}),
            ):
                code, out, err = run_main(request, state_home=self.root)
                self.assertEqual((code, err), (0, ""))
                response = json.loads(out)
                self.assertEqual("content" in response, expected)
                if not expected:
                    self.assertIn("Failed to fetch", response["output"])
                    continue
                text, image = response["content"]
                self.assertEqual(text, {"type": "input_text", "text": response["output"]})
                self.assertIn(f"Failed to fetch {broken}: Internal Error", text["text"])
                self.assertIn("not a PDF the renderer can read", self.log_text())
                prefix = "data:image/png;base64,"
                self.assertEqual(sorted(image), ["image_url", "type"])
                self.assertEqual(image["type"], "input_image")
                self.assertTrue(image["image_url"].startswith(prefix))
                png = base64.b64decode(image["image_url"].removeprefix(prefix))
                self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")

    def test_kagi_failures_answer_as_the_service_503(self) -> None:
        """Any Kagi failure fails the call with Codex's 503 text; the reason goes to the log."""
        errors: list[Exception] = [
            client.SessionError(),
            client.SignedOutError(),
            client.ChallengeError(),
            client.SearchError("Kagi answered HTTP 502"),
        ]
        for error in errors:
            with (
                self.subTest(error=type(error).__name__),
                unittest.mock.patch.object(cli, "run", FakeSearch(error)),
            ):
                code, out, err = run_main(
                    {
                        "id": SESSION,
                        "commands": {
                            "search_query": [{"q": "guix"}],
                            "time": [{"utc_offset": "+00:00"}],
                        },
                    },
                    state_home=self.root,
                )
                self.assert_unavailable(code, out, err)
                self.assertIn(str(error), self.log_text())

    def test_log_file_is_private(self) -> None:
        """The log file is created 0600 in a 0700 directory; the state home keeps its mode."""
        self.root.chmod(0o755)
        run_main(b"not json", state_home=self.root)
        log = self.root / "kagi-search" / "web-run.log"
        self.assertEqual(stat.S_IMODE(log.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(log.parent.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o755)

    def test_state_chores_never_cost_the_response(self) -> None:
        """A failing record or prune still prints the response; the reason goes to the log."""
        cases: list[tuple[str, Exception]] = [
            ("record", OSError(28, "No space left on device")),
            ("record", RuntimeError("unexpected")),
            ("prune", webrun.StateError("unreadable")),
        ]
        for method, error in cases:
            with (
                self.subTest(method=method, error=error),
                unittest.mock.patch.object(webrun.Session, method, side_effect=error),
            ):
                code, out, err = run_main(
                    {"id": SESSION, "commands": {"time": [{"utc_offset": "+00:00"}]}},
                    state_home=self.root,
                )
                self.assertEqual((code, err), (0, ""))
                self.assertIn("The time in UTC+00:00", json.loads(out)["output"])
                self.assertIn(
                    f"could not {'save' if method == 'record' else 'remove'}", self.log_text()
                )

    def test_an_internal_error_answers_as_the_service_503(self) -> None:
        """An unforeseen error fails the call with Codex's 503 text; the traceback is logged."""
        with unittest.mock.patch.object(
            webrun.Session, "begin", side_effect=RuntimeError("lock bug")
        ):
            code, out, err = run_main({"id": SESSION, "commands": {}}, state_home=self.root)
        self.assert_unavailable(code, out, err)
        self.assertIn("RuntimeError: lock bug", self.log_text())
        self.assertIn("Traceback", self.log_text())

    def test_malformed_requests(self) -> None:
        """Requests that do not parse fail with Codex's 503 text and claim no state."""
        cases: list[object] = [
            b"not json",
            b"[" * 100_000 + b"]" * 100_000,
            [],
            {"id": SESSION},
            {"id": 1, "commands": {}},
            {"id": SESSION, "commands": {"response_length": "huge"}},
            {"id": SESSION, "commands": {"click": [{"ref_id": "turn0view0"}]}},
            {"id": SESSION, "commands": {"open": [{"ref_id": "x", "lineno": -1}]}},
            {"id": SESSION, "commands": {"search_query": "guix"}},
        ]
        for request in cases:
            with self.subTest(request=str(request)[:40]):
                code, out, err = run_main(request, state_home=self.root)
                self.assert_unavailable(code, out, err)
        self.assertFalse(self.directory.exists())
