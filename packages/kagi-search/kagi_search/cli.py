# Copyright (c) 2026 Bad3r
"""Command line of the kagi-search app."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import sys
import time
import traceback
from dataclasses import asdict
from typing import TYPE_CHECKING

from browser_fetch import cli as fetch_cli
from browser_fetch import cookies as jar
from browser_fetch import fetch, tools

from kagi_search import client
from kagi_search.log import FileLog, state_root
from kagi_search.page import Hit, UnrecognizedPageError

if TYPE_CHECKING:
    import datetime as dt
    from pathlib import Path

SESSION_EXIT = 3
SIGNED_OUT_EXIT = 4
CHALLENGE_EXIT = 5
FAILURE_EXIT = 6


def _limit(value: str) -> int:
    limit = int(value)
    if limit < 0:
        msg = f"{value} is negative"
        raise argparse.ArgumentTypeError(msg)
    return limit


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="kagi-search",
        description=(
            "Search Kagi with the session in browser-fetch's cookie jar, through browser-fetch's "
            "curl-impersonate. Sign in with 'browser-fetch login https://kagi.com'."
        ),
        epilog=(
            f"Exit status: {SESSION_EXIT} no Kagi session in browser-fetch's profile, "
            f"{SIGNED_OUT_EXIT} Kagi rejected it, {CHALLENGE_EXIT} bot challenge, "
            f"{FAILURE_EXIT} other failure."
        ),
    )
    parser.add_argument("query", nargs="+", help="the search query")
    parser.add_argument("--json", action="store_true", help="print JSON instead of text")
    parser.add_argument(
        "--limit", type=_limit, default=10, help="at most this many hits; 0 for every hit"
    )
    parser.add_argument("--allow", action="append", default=[], metavar="DOMAIN")
    parser.add_argument("--block", action="append", default=[], metavar="DOMAIN")
    return parser


def run(  # noqa: PLR0913 - keyword-only options of the search
    query: str,
    *,
    allowed: list[str] | None = None,
    blocked: list[str] | None = None,
    limit: int | None = 10,
    since: dt.date | None = None,
    until: float | None = None,
) -> list[Hit]:
    """Search with the Kagi session in browser-fetch's jar, ending by the monotonic until if given.

    Raises SessionError, CookieError, SearchError or UnrecognizedPageError;
    what browser-fetch could not do, such as save a cookie, is logged.
    """
    seconds = client.DEADLINE_SECONDS
    if until is not None:
        seconds = min(seconds, until - time.monotonic())
    with fetch_cli.workspace() as workdir:
        settings = fetch.Settings(
            curl=tools.CURL,
            browser=fetch_cli.camoufox(workdir),
            workdir=workdir,
            save_dir=fetch_cli.save_dir(),
            browser_mode="never",
            deadline=seconds,
        )
        requests = fetch.Client(settings)
        try:
            return client.search(
                query, requests, allowed=allowed, blocked=blocked, limit=limit, since=since
            )
        finally:
            log = FileLog(log_path())
            for warning in requests.close():
                log(f"search {query!r}: warning: {warning}")


def render(hits: list[Hit]) -> str:
    """Return the hits as numbered text blocks."""
    if not hits:
        return "No results."
    blocks = [
        "\n".join(filter(None, [f"{index}. {hit.title}", hit.url, hit.snippet]))
        for index, hit in enumerate(hits, start=1)
    ]
    return "\n\n".join(blocks)


EXIT_CODES: tuple[tuple[type[Exception], int], ...] = (
    (client.SessionError, SESSION_EXIT),
    (jar.CookieError, SESSION_EXIT),
    (client.SignedOutError, SIGNED_OUT_EXIT),
    (client.ChallengeError, CHALLENGE_EXIT),
    (client.SearchError, FAILURE_EXIT),
    (UnrecognizedPageError, FAILURE_EXIT),
)


def _discard_stdout() -> None:
    """Point stdout at /dev/null, so nothing buffered is retried against a closed pipe at exit."""
    with contextlib.suppress(OSError):
        null = os.open(os.devnull, os.O_WRONLY)
        try:
            os.dup2(null, sys.stdout.fileno())
        finally:
            os.close(null)


def log_path() -> Path:
    """Return the log file that holds the reasons behind failed searches."""
    return state_root() / "kagi-search.log"


def main(argv: list[str] | None = None) -> int:
    """Run the command line and return its exit status; failures are also logged."""
    args = _parser().parse_args(argv)
    query = " ".join(args.query)
    os.umask(0o077)
    fetch_cli.exit_on_signals()
    try:
        hits = run(query, allowed=args.allow, blocked=args.block, limit=args.limit or None)
        if args.json:
            print(json.dumps({"query": query, "hits": [asdict(hit) for hit in hits]}))
        else:
            print(render(hits))
        sys.stdout.flush()
    except Exception as error:  # noqa: BLE001 - every failure is reported and logged
        if isinstance(error, BrokenPipeError):
            _discard_stdout()
        known = next((c for kind, c in EXIT_CODES if isinstance(error, kind)), None)
        detail = "" if known else "\n" + "".join(traceback.format_exception(error))
        FileLog(log_path())(f"search {query!r} failed: {type(error).__name__}: {error}{detail}")
        print(f"kagi-search: {' '.join(str(error).split())}", file=sys.stderr)
        return known or FAILURE_EXIT
    return 0
