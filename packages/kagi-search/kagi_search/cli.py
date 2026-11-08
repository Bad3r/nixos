# Copyright (c) 2026 Bad3r
"""Command line of the kagi-search app."""

from __future__ import annotations

import argparse
import json
import os
import sys
import traceback
from dataclasses import asdict
from typing import TYPE_CHECKING

from kagi_search import client, cookie
from kagi_search.log import FileLog, state_root
from kagi_search.page import Hit, UnrecognizedPageError

if TYPE_CHECKING:
    from pathlib import Path

SESSION_EXIT = 3
SIGNED_OUT_EXIT = 4
CHALLENGE_EXIT = 5
FAILURE_EXIT = 6


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="kagi-search",
        description="Search Kagi with the session of LibreWolf's default profile.",
        epilog=(
            f"Exit status: {SESSION_EXIT} no session in LibreWolf, {SIGNED_OUT_EXIT} Kagi "
            f"rejected it, {CHALLENGE_EXIT} bot challenge, {FAILURE_EXIT} other failure."
        ),
    )
    parser.add_argument("query", nargs="+", help="the search query")
    parser.add_argument("--json", action="store_true", help="print JSON instead of text")
    parser.add_argument("--limit", type=int, default=10, help="at most this many hits")
    parser.add_argument("--allow", action="append", default=[], metavar="DOMAIN")
    parser.add_argument("--block", action="append", default=[], metavar="DOMAIN")
    return parser


def run(
    query: str,
    *,
    allowed: list[str] | None = None,
    blocked: list[str] | None = None,
    limit: int = 10,
) -> list[Hit]:
    """Search with LibreWolf's session; raises SessionError or SearchError."""
    session = cookie.read_session(cookie.default_profile(cookie.librewolf_root()))
    return client.search(query, session, allowed=allowed, blocked=blocked, limit=limit)


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
    (cookie.SessionError, SESSION_EXIT),
    (client.SignedOutError, SIGNED_OUT_EXIT),
    (client.ChallengeError, CHALLENGE_EXIT),
    (client.SearchError, FAILURE_EXIT),
    (UnrecognizedPageError, FAILURE_EXIT),
)


def log_path() -> Path:
    """Return the log file that holds the reasons behind failed searches."""
    return state_root() / "kagi-search.log"


def main(argv: list[str] | None = None) -> int:
    """Run the command line and return its exit status; failures are also logged."""
    args = _parser().parse_args(argv)
    query = " ".join(args.query)
    try:
        hits = run(query, allowed=args.allow, blocked=args.block, limit=max(args.limit, 1))
        if args.json:
            print(json.dumps({"query": query, "hits": [asdict(hit) for hit in hits]}))
        else:
            print(render(hits))
        sys.stdout.flush()
    except Exception as error:  # noqa: BLE001 - every failure is reported and logged
        if isinstance(error, BrokenPipeError):
            # Nothing buffered may be retried against the closed pipe at exit.
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        known = next((c for kind, c in EXIT_CODES if isinstance(error, kind)), None)
        detail = "" if known else "\n" + "".join(traceback.format_exception(error))
        FileLog(log_path())(f"search {query!r} failed: {type(error).__name__}: {error}{detail}")
        print(f"kagi-search: {' '.join(str(error).split())}", file=sys.stderr)
        return known or FAILURE_EXIT
    return 0
