# Copyright (c) 2026 Bad3r
"""Searches through browser-fetch: its jar, its curl-impersonate request, and Kagi's answers.

The jar is a cookies.sqlite at Gecko's schema under a throwaway
XDG_STATE_HOME, and curl a stand-in that records what it was asked.
"""

import contextlib
import datetime as dt
import fcntl
import io
import json
import os
import shutil
import sqlite3
import stat
import sys
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path
from typing import Any, cast
from urllib.parse import parse_qs, urlsplit

from browser_fetch import browser, curl, tools, urls
from browser_fetch import cookies as jar
from kagi_search import cli, client

from tests.test_page import NO_RESULTS, RESULTS

FAKE_CURL = """\
import json, os, sys
args = sys.argv[1:]
config = open(args[args.index("--config") + 1]).read()
with open(os.environ["FAKE_CURL_LOG"], "a") as log:
    log.write(json.dumps({"argv": args, "config": config,
                          "https_proxy": os.environ.get("https_proxy")}) + "\\n")
answer = json.load(open(os.environ["FAKE_CURL_ANSWER"]))
with open(args[args.index("--output") + 1], "w") as body:
    body.write(answer.get("body", ""))
given = answer.get("headers", {})
headers = {k.lower(): v if isinstance(v, list) else [v] for k, v in given.items()}
pinned = args[args.index("--resolve") + 1].split(":", 2)[2].split(",")[0].strip("[]")
sys.stdout.write(f"{answer['status']:03d}\\n000\\n{pinned}\\n{json.dumps(headers)}")
"""
PUBLIC = "93.184.215.14"
SIGN_IN = "run `browser-fetch login https://kagi.com` and sign in"
NO_SESSION = f"kagi-search: no Kagi session in browser-fetch's profile; {SIGN_IN}\n"
DAY_MS = 86_400_000


def now_ms() -> int:
    """The time in the unit of Gecko's expiry column."""
    return time.time_ns() // 1_000_000


class SearchTest(unittest.TestCase):
    """kagi-search's command line against a stand-in curl and a real jar."""

    def setUp(self) -> None:
        """Throwaway state, runtime and cache directories, the stand-in curl, a public resolver."""
        self.tmp = Path(tempfile.mkdtemp(prefix="kagi-search-test-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        for name in ("state", "runtime", "cache", "curl"):
            (self.tmp / name).mkdir(mode=0o700)
        fake = self.tmp / "curl" / "curl"
        fake.write_text(f"#!{sys.executable} -I\n{FAKE_CURL}")
        fake.chmod(stat.S_IRWXU)
        self.log = self.tmp / "curl" / "log.jsonl"
        self.answer({"status": 200, "body": RESULTS, "headers": {}})
        env = {
            "XDG_STATE_HOME": str(self.tmp / "state"),
            "XDG_RUNTIME_DIR": str(self.tmp / "runtime"),
            "XDG_CACHE_HOME": str(self.tmp / "cache"),
            "FAKE_CURL_LOG": str(self.log),
            "FAKE_CURL_ANSWER": str(self.tmp / "curl" / "answer.json"),
        }
        for patch in (
            unittest.mock.patch.dict(os.environ, env),
            unittest.mock.patch.object(tools, "CURL", str(fake)),
            unittest.mock.patch.object(urls, "lookup", return_value=[PUBLIC]),
        ):
            patch.start()
            self.addCleanup(patch.stop)
        self.profile = self.tmp / "state" / "browser-fetch" / browser.PROFILE
        self.database = self.profile / jar.DB_NAME

    def answer(self, answer: dict[str, Any]) -> None:
        """What the stand-in curl answers every request with."""
        (self.tmp / "curl" / "answer.json").write_text(json.dumps(answer))

    def jar_rows(self, *rows: dict[str, Any], version: int = 17) -> None:
        """Create the profile's cookies.sqlite at Gecko's schema, holding the rows."""
        self.profile.mkdir(parents=True, mode=0o700)
        db = sqlite3.connect(self.database)
        try:
            db.execute(f"pragma user_version = {version}")
            db.execute(jar.CREATE_TABLE)
            for row in rows:
                created = time.time_ns() // 1000
                full = {
                    "originAttributes": "",
                    "path": "/",
                    "expiry": now_ms() + DAY_MS,
                    "lastAccessed": created,
                    "creationTime": created,
                    "isSecure": 1,
                    "isHttpOnly": 1,
                    "sameSite": 1,
                    "schemeMap": 2,
                    "isPartitionedAttributeSet": 0,
                    "updateTime": created,
                    **row,
                }
                columns = ", ".join(full)
                marks = ", ".join("?" for _ in full)
                insert = f"insert into moz_cookies ({columns}) values ({marks})"  # noqa: S608
                db.execute(insert, [*full.values()])
            db.commit()
        finally:
            db.close()

    def stored(self) -> dict[tuple[str, str], str]:
        """The jar's rows as (host, name) to value."""
        db = sqlite3.connect(self.database)
        try:
            rows = db.execute("select host, name, value from moz_cookies").fetchall()
        finally:
            db.close()
        return {(host, name): value for host, name, value in rows}

    def calls(self) -> list[dict[str, Any]]:
        """Each stand-in curl call's argv, config and proxy variable."""
        if not self.log.exists():
            return []
        return [cast("dict[str, Any]", json.loads(x)) for x in self.log.read_text().splitlines()]

    def run_cli(self, *argv: str) -> tuple[int, str, str]:
        """Run kagi-search's main; return its status, stdout and stderr."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = cli.main(list(argv))
        return status, out.getvalue(), err.getvalue()

    def session(self, value: str = "tok", **row: Any) -> dict[str, Any]:  # noqa: ANN401
        """A kagi_session row as Firefox stores Kagi's host-only cookie."""
        return {"name": "kagi_session", "value": value, "host": "kagi.com", **row}

    def test_the_session_rides_the_request_of_browser_fetch(self) -> None:
        """One curl-impersonate request with the jar's Kagi cookies and the fingerprint headers."""
        self.jar_rows(
            self.session(),
            {"name": "pref", "value": "dark", "host": ".kagi.com"},
            {"name": "other", "value": "x", "host": "example.org"},
            {
                "name": "partitioned",
                "value": "p",
                "host": "kagi.com",
                "originAttributes": "^partitionKey=%28https%2Cexample.org%29",
                "isPartitionedAttributeSet": 1,
            },
        )
        fingerprint = {
            "browser": tools.CAMOUFOX_VERSION,
            "headers": {"user-agent": "Camoufox-UA", "accept-language": "en-GB,en"},
        }
        (self.profile.parent / browser.FINGERPRINT).write_text(json.dumps(fingerprint))
        status, out, err = self.run_cli(
            "--json", "--allow", "wiki.nixos.org", "--block", "b.org", "--", "nix flakes"
        )
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(
            [h["url"] for h in json.loads(out)["hits"]], ["https://wiki.nixos.org/wiki/Flakes"]
        )
        (call,) = self.calls()
        argv: list[str] = call["argv"]
        url = urlsplit(argv[-1])
        self.assertEqual((url.scheme, url.netloc, url.path), ("https", "kagi.com", "/html/search"))
        self.assertEqual(parse_qs(url.query), {"q": ["nix flakes site:wiki.nixos.org -site:b.org"]})
        self.assertEqual(argv[argv.index("--impersonate") + 1], curl.IMPERSONATE)
        self.assertEqual(argv[argv.index("--resolve") + 1], f"kagi.com:443:{PUBLIC}")
        self.assertNotIn("tok", " ".join(argv))
        headers = [
            line.removeprefix('header = "').removesuffix('"')
            for line in call["config"].splitlines()
        ]
        self.assertIn("User-Agent: Camoufox-UA", headers)
        self.assertIn("Accept-Language: en-GB,en", headers)
        cookie = next(h for h in headers if h.startswith("Cookie: "))
        self.assertEqual(
            sorted(cookie.removeprefix("Cookie: ").split("; ")), ["kagi_session=tok", "pref=dark"]
        )

    def test_since_adds_a_start_date(self) -> None:
        """A start date reaches Kagi as the from_date of its date-range filter."""
        self.jar_rows(self.session())
        cli.run("nix", since=dt.date(2026, 11, 1))
        query = parse_qs(urlsplit(self.calls()[0]["argv"][-1]).query)
        self.assertEqual(query, {"q": ["nix"], "from_date": ["2026-11-01"]})

    def test_limit(self) -> None:
        """At most limit hits come back, and every hit without one."""
        self.jar_rows(self.session())
        self.assertEqual([h.title for h in cli.run("nix", limit=1)], ["NixOS & Nix"])
        self.assertGreater(len(cli.run("nix", limit=None)), 1)

    def test_no_results_is_an_empty_list(self) -> None:
        """Kagi's no-results answer is no hits, not an error."""
        self.jar_rows(self.session())
        self.answer({"status": 200, "body": NO_RESULTS, "headers": {}})
        self.assertEqual(cli.run("x"), [])

    def test_kagis_cookie_changes_reach_the_jar(self) -> None:
        """What Kagi's response sets, replaces or deletes is in cookies.sqlite afterwards."""
        self.jar_rows(self.session("old"), {"name": "gone", "value": "1", "host": "kagi.com"})
        self.answer(
            {
                "status": 200,
                "body": RESULTS,
                "headers": {
                    "Set-Cookie": [
                        "kagi_session=renewed; Max-Age=86400; Path=/; Secure; HttpOnly",
                        "gone=; Max-Age=0; Path=/",
                        "added=1; Max-Age=3600; Path=/; Secure",
                        "fleeting=1; Path=/",
                    ]
                },
            }
        )
        status, _, err = self.run_cli("--json", "nix")
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(
            self.stored(),
            {("kagi.com", "kagi_session"): "renewed", ("kagi.com", "added"): "1"},
        )

    def test_no_session_sends_nothing_and_exits_3(self) -> None:
        """Without a live kagi_session for kagi.com the search stops before any request."""
        cases: dict[str, list[dict[str, Any]] | None] = {
            "no database": None,
            "no cookie": [{"name": "pref", "value": "dark", "host": "kagi.com"}],
            "expired": [self.session(expiry=now_ms() - 1000)],
            "another host": [self.session(host="kagi.com.example.org")],
            "partitioned": [
                self.session(
                    originAttributes="^partitionKey=%28https%2Cexample.org%29",
                    isPartitionedAttributeSet=1,
                )
            ],
        }
        for name, rows in cases.items():
            with self.subTest(name):
                shutil.rmtree(self.profile.parent, ignore_errors=True)
                if rows is not None:
                    self.jar_rows(*rows)
                self.assertEqual(self.run_cli("nix"), (cli.SESSION_EXIT, "", NO_SESSION))
                self.assertEqual(self.calls(), [])

    def test_a_busy_profile_says_so(self) -> None:
        """A login holding the profile keeps the jar unread, and the error names that."""
        self.jar_rows(self.session())
        holder = os.open(self.profile.parent / browser.LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, holder)
        fcntl.flock(holder, fcntl.LOCK_EX)
        status, out, err = self.run_cli("nix")
        self.assertEqual((status, out), (cli.SESSION_EXIT, ""))
        self.assertIn("busy", err)
        self.assertTrue(err.endswith(f"; {SIGN_IN}\n"))
        self.assertEqual(err.count("\n"), 1)
        self.assertEqual(self.calls(), [])

    def test_an_unusable_jar_exits_3(self) -> None:
        """A cookies.sqlite at another schema version is never read, and says why."""
        self.jar_rows(self.session(), version=18)
        status, out, err = self.run_cli("nix")
        self.assertEqual((status, out), (cli.SESSION_EXIT, ""))
        self.assertIn("schema version 18", err)

    def test_kagis_answers_map_to_exit_codes(self) -> None:
        """Sign-in redirect 4, challenge 5, any other status 6, each with its reason."""
        self.jar_rows(self.session())
        cases = [
            (302, "https://kagi.com/signin?p=invalid_token", cli.SIGNED_OUT_EXIT, SIGN_IN),
            (302, "/turnstile?r=/html/search", cli.CHALLENGE_EXIT, "bot challenge"),
            (302, "https://kagi.com/elsewhere", cli.FAILURE_EXIT, "redirected to"),
            (503, "", cli.FAILURE_EXIT, "HTTP 503"),
        ]
        for code, location, expected, reason in cases:
            with self.subTest(code=code, location=location):
                headers = {"Location": location} if location else {}
                self.answer({"status": code, "body": "", "headers": headers})
                status, out, err = self.run_cli("nix")
                self.assertEqual((status, out), (expected, ""))
                self.assertIn(reason, err)

    def test_curl_gets_the_proxy_browser_fetch_uses(self) -> None:
        """Curl runs with the caller's proxy variables, as in a fetch."""
        self.jar_rows(self.session())
        with unittest.mock.patch.dict(os.environ, {"https_proxy": "http://proxy.example:3128"}):
            self.assertEqual(self.run_cli("nix")[0], 0)
        self.assertEqual(self.calls()[0]["https_proxy"], "http://proxy.example:3128")

    def test_no_work_directory_is_left(self) -> None:
        """The request's work directory, which held the Cookie header, goes with the run."""
        self.jar_rows(self.session())
        self.run_cli("nix")
        self.assertEqual(list((self.tmp / "runtime").iterdir()), [])

    def test_the_errors_name_the_login(self) -> None:
        """A missing or rejected session tells the user to sign in with browser-fetch login."""
        self.assertEqual(
            str(client.SessionError()),
            f"no Kagi session in browser-fetch's profile; {SIGN_IN}",
        )
        self.assertEqual(
            str(client.SignedOutError()),
            "Kagi rejected the session in browser-fetch's profile (signed out or expired); "
            f"{SIGN_IN}",
        )
