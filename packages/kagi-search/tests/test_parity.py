# Copyright (c) 2026 Bad3r
"""Calls the real service answered, replayed against the emulator byte for byte."""

import datetime as dt
import json
import re
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path
from typing import cast, override

from kagi_search import cli, client, fetch, webrun
from kagi_search.page import Hit

from tests.captured import CAPTURED
from tests.test_webrun import FakeFetch, FakeSearch, run_main

SESSION = "parity-session"
EXAMPLE = "https://example.com/"
EXAMPLE_HTML = (
    "<title>Example Domain</title><p>This domain is for use in documentation examples "
    "without needing permission. This is not a service; avoid relying on it for testing "
    "and monitoring purposes.</p>"
)
INVALID = "https://does-not-exist-zq7x.invalid/"
ARXIV = "https://arxiv.org/pdf/1706.03762"
PNG = "https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_1.png"
PAGES = {
    EXAMPLE: fetch.Page(EXAMPLE, "text/html", EXAMPLE_HTML, redirected=False),
    ARXIV: fetch.Page(ARXIV, "application/pdf", None, redirected=False, pdf_pages=15),
    PNG: fetch.Page(PNG, "image/png", None, redirected=False),
}
EXAMPLE_REF = webrun.Ref(EXAMPLE, "Example Domain", [])
ARXIV_REF = webrun.Ref(ARXIV, "", [])
FORBIDDEN = re.compile(r"kagi|browser-fetch|camoufox|backend", re.IGNORECASE)


class Replay:
    """One session, seeded at a turn, answering with fake pages and searches."""

    def __init__(self, directory: Path, turn: int, refs: dict[str, webrun.Ref]) -> None:
        """Seed the session's state at the turn with the refs."""
        self.directory = directory
        self.search = FakeSearch([])
        self.fetch = FakeFetch(PAGES)
        self.logged: list[str] = []
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"{webrun.state_name(SESSION)}.json"
        path.write_text(webrun.State(turn, refs).dump(), encoding="utf-8")

    def call(
        self, commands: dict[str, object], now: dt.datetime | None = None
    ) -> dict[str, object]:
        """Answer one request with the commands at the given time."""
        stamp = now or dt.datetime(2026, 11, 7, 22, 0, tzinfo=dt.UTC)
        return webrun.handle(
            {"id": SESSION, "model": "gpt", "commands": commands},
            search=self.search,
            fetch=self.fetch,
            directory=self.directory,
            now=lambda: stamp,
            log=self.logged.append,
        )


def at(hour: int, minute: int, second: int) -> dt.datetime:
    """Return a UTC moment on 2026-11-07."""
    return dt.datetime(2026, 11, 7, hour, minute, second, tzinfo=dt.UTC)


# Record number, seeded turn, seeded refs, commands, and the moment of the call.
CASES: list[tuple[int, int, dict[str, webrun.Ref], dict[str, object], dt.datetime | None]] = [
    (0, 0, {}, {"open": [{"ref_id": INVALID}]}, None),
    (3, 3, {}, {"open": [{"ref_id": "turn9view9"}]}, None),
    (
        4,
        4,
        {},
        {
            "open": [
                {"ref_id": EXAMPLE},
                {"ref_id": INVALID},
                {"ref_id": "https://httpbin.org/status/404"},
            ]
        },
        None,
    ),
    (5, 0, {}, {"open": [{"ref_id": EXAMPLE}]}, None),
    (6, 1, {"turn0view0": EXAMPLE_REF}, {"click": [{"ref_id": "turn0view0", "id": 99}]}, None),
    (7, 2, {}, {"click": [{"ref_id": "turn9view9", "id": 1}]}, None),
    (8, 3, {}, {"find": [{"ref_id": "turn9view9", "pattern": "example"}]}, None),
    (
        9,
        4,
        {"turn0view0": EXAMPLE_REF},
        {"find": [{"ref_id": "turn0view0", "pattern": "zqxjkvw"}]},
        None,
    ),
    (
        10,
        5,
        {"turn0view0": EXAMPLE_REF},
        {"find": [{"ref_id": "turn0view0", "pattern": "documentation"}]},
        None,
    ),
    (11, 6, {"turn0view0": EXAMPLE_REF}, {"open": [{"ref_id": "turn0view0", "lineno": 500}]}, None),
    (
        12,
        7,
        {"turn0view0": EXAMPLE_REF},
        {
            "find": [
                {"ref_id": "turn0view0", "pattern": "documentation"},
                {"ref_id": "turn0view0", "pattern": "zqxjkvw"},
            ]
        },
        None,
    ),
    (13, 0, {}, {"search_query": [{"q": '"qzv8xk3m9wplr7tj2hn5ybd4fc6gsa1e"'}]}, None),
    (16, 0, {}, {"open": [{"ref_id": EXAMPLE}, {"ref_id": "turn9view9"}]}, None),
    (
        19,
        1,
        {"turn0view0": ARXIV_REF},
        {"screenshot": [{"ref_id": "turn0view0", "pageno": 0}]},
        None,
    ),
    (
        20,
        2,
        {"turn0view0": ARXIV_REF},
        {"screenshot": [{"ref_id": "turn0view0", "pageno": 999}]},
        None,
    ),
    (21, 3, {}, {"open": [{"ref_id": PNG}]}, None),
    (
        23,
        5,
        {"turn4view0": EXAMPLE_REF},
        {"screenshot": [{"ref_id": "turn4view0", "pageno": 0}]},
        None,
    ),
    (27, 3, {}, {"sports": [{"fn": "schedule", "league": "nba", "num_games": 3}]}, None),
    (28, 4, {}, {"time": [{"utc_offset": "+03:00"}]}, at(22, 39, 43)),
    (29, 5, {}, {"finance": [{"ticker": "ZQXZQXZQ", "type": "equity", "market": "USA"}]}, None),
    (
        34,
        3,
        {},
        {
            "open": [{"ref_id": EXAMPLE}],
            "finance": [{"ticker": "ZQXZQXZQ", "type": "equity", "market": "USA"}],
        },
        None,
    ),
    (35, 0, {}, {"time": [{"utc_offset": "+03:00"}, {"utc_offset": "-05:00"}]}, at(22, 41, 42)),
    (
        36,
        1,
        {},
        {
            "search_query": [{"q": '"qzv8xk3m9wplr7tj2hn5ybd4fc6gsa1e"'}],
            "open": [{"ref_id": EXAMPLE}],
            "time": [{"utc_offset": "+00:00"}],
        },
        at(22, 41, 49),
    ),
    (37, 0, {}, {"time": [{"utc_offset": "bogus"}]}, None),
]


class ParityTestCase(unittest.TestCase):
    """A fresh state directory per test."""

    @override
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.directory = self.root / "kagi-search" / "web-run"


class CaptureTest(ParityTestCase):
    """Each captured call, replayed in a session seeded like the captured one."""

    def test_captured_calls_reproduce_byte_for_byte(self) -> None:
        """Output and results equal the captured service's exactly."""
        self.assertEqual({case[0] for case in CASES}, set(CAPTURED))
        for record, turn, refs, commands, now in CASES:
            with self.subTest(record=record):
                directory = self.directory / str(record)
                response = Replay(directory, turn, refs).call(commands, now)
                expected_output, expected_results = CAPTURED[record]
                self.assertEqual(response["output"], expected_output)
                self.assertEqual(response["results"], expected_results)
                self.assertIsNone(response["encrypted_output"])

    def test_an_unknown_ref_still_takes_a_turn(self) -> None:
        """The failed call consumes its turn, as the service's numbering shows."""
        replay = Replay(self.directory, 3, {})
        replay.call({"open": [{"ref_id": "turn9view9"}]})
        response = replay.call({"open": [{"ref_id": EXAMPLE}]})
        self.assertIn("turn4view0", cast("str", response["output"]))

    def test_an_empty_query_beside_hits_adds_nothing(self) -> None:
        """Only when no query finds anything does the empty-search block appear."""
        replay = Replay(self.directory, 0, {})
        hits = [Hit("Example Domains", "https://www.iana.org/help/example-domains", "s")]

        def search(
            query: str,
            *,
            allowed: list[str] | None,
            blocked: list[str] | None,
            limit: int,
            since: dt.date | None,
        ) -> list[Hit]:
            del allowed, blocked, limit, since
            return hits if query == "iana" else []

        response = webrun.handle(
            {"id": SESSION, "commands": {"search_query": [{"q": "iana"}, {"q": "nothing"}]}},
            search=search,
            fetch=replay.fetch,
            directory=self.directory,
            now=lambda: at(22, 0, 0),
            log=replay.logged.append,
        )
        self.assertNotIn("Empty search results", cast("str", response["output"]))
        self.assertEqual(len(cast("list[object]", response["results"])), 1)


class DeadlineTest(ParityTestCase):
    """A call answers before its deadline whatever its fetches do."""

    def test_slow_fetches_stop_at_the_call_deadline(self) -> None:
        """Operations not started by the deadline get the not-accessible block."""

        class SlowFetch(FakeFetch):
            def __init__(self) -> None:
                super().__init__(PAGES)
                self.deadlines: list[float] = []

            @override
            def __call__(self, url: str, deadline: float) -> fetch.Page:
                self.deadlines.append(deadline)
                time.sleep(SLOW_FETCH_SECONDS)
                return super().__call__(url, deadline)

        replay = Replay(self.directory, 0, {})
        replay.fetch = slow = SlowFetch()
        urls = [f"{EXAMPLE}?page={index}" for index in range(8)]
        slow.pages |= {
            url: fetch.Page(url, "text/html", EXAMPLE_HTML, redirected=False) for url in urls
        }
        started = time.monotonic()
        with (
            unittest.mock.patch.object(webrun, "CALL_DEADLINE_SECONDS", TEST_CALL_SECONDS),
            unittest.mock.patch.object(webrun, "PAGE_START_MARGIN_SECONDS", TEST_MARGIN_SECONDS),
        ):
            response = replay.call({"open": [{"ref_id": url} for url in urls]})
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, TEST_CALL_SECONDS)
        self.assertLess(len(slow.urls), len(urls))
        self.assertTrue(all(deadline <= started + TEST_CALL_SECONDS for deadline in slow.deadlines))
        blocks = cast("str", response["output"]).split(webrun.BLOCK_SEPARATOR)
        self.assertEqual(len(blocks), len(urls))
        self.assertTrue(blocks[-1].endswith(f"URL {urls[-1]} is not accessible via this tool."))

    def test_searches_do_not_start_near_the_deadline(self) -> None:
        """A search that could outlast the deadline is not started."""
        replay = Replay(self.directory, 0, {})
        replay.search = FakeSearch([Hit("A", "https://a.org/", "s")])
        with unittest.mock.patch.object(webrun, "CALL_DEADLINE_SECONDS", TEST_MARGIN_SECONDS):
            response = replay.call({"search_query": [{"q": "a"}]})
        self.assertEqual(replay.search.calls, [])
        self.assertEqual(response["output"], webrun.EMPTY_SEARCH)


SLOW_FETCH_SECONDS = 0.15
TEST_CALL_SECONDS = 1.0
TEST_MARGIN_SECONDS = 0.5


class LeakTest(ParityTestCase):
    """Nothing the model sees names the real search engine, browser, or program."""

    def test_no_output_names_what_answers(self) -> None:
        """Across succeeding and failing calls, output, results, and stderr stay clean."""
        hits = [Hit("A", "https://a.org/", "snippet")]
        requests: list[dict[str, object]] = [
            {"search_query": [{"q": "a"}]},
            {"search_query": [{"q": ""}]},
            {"open": [{"ref_id": EXAMPLE}, {"ref_id": INVALID}, {"ref_id": ARXIV}]},
            {"open": [{"ref_id": "turn9view9"}]},
            {"open": [{"ref_id": "http://127.0.0.1/"}, {"ref_id": "file:///etc/passwd"}]},
            {"screenshot": [{"ref_id": EXAMPLE, "pageno": 0}]},
            {"time": [{"utc_offset": "nope"}], "finance": [{"ticker": "X", "type": "equity"}]},
            {"sports": [{"fn": "standings", "league": "nfl"}]},
        ]
        failures: list[Exception] = [
            client.SessionError(),
            client.SignedOutError(),
            client.ChallengeError(),
            client.SearchError("Kagi answered HTTP 503"),
        ]
        seen: list[str] = []
        for index, commands in enumerate(requests):
            with unittest.mock.patch.object(cli, "run", FakeSearch(hits)):
                _, out, err = run_main(
                    {"id": f"leak-{index}", "commands": commands}, state_home=self.root
                )
            seen += [out, err]
        for index, failure in enumerate(failures):
            with unittest.mock.patch.object(cli, "run", FakeSearch(failure)):
                _, out, err = run_main(
                    {"id": f"fail-{index}", "commands": {"search_query": [{"q": "a"}]}},
                    state_home=self.root,
                )
            self.assertEqual(err, webrun.SERVICE_UNAVAILABLE)
            seen += [out, err]
        for text in seen:
            self.assertIsNone(FORBIDDEN.search(text), text[:200])
        log = (self.root / "kagi-search" / "web-run.log").read_text(encoding="utf-8")
        self.assertIn("no Kagi session in browser-fetch's profile", log)
        self.assertTrue(all(json.loads(text) for text in seen[0::2] if text))
