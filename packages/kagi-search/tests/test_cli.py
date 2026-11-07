# Copyright (c) 2026 Bad3r
"""Command line output and exit codes."""

import contextlib
import io
import json
import unittest
import unittest.mock

from kagi_search import cli, client, cookie
from kagi_search.page import Hit, UnrecognizedPageError

HITS = [
    Hit("NixOS", "https://nixos.org/", "Declarative."),
    Hit("Wiki", "https://wiki.nixos.org/", ""),
]


def call(argv: list[str], outcome: list[Hit] | Exception) -> tuple[int, str, str]:
    """Run main with run stubbed to the outcome; return the code, stdout, and stderr."""
    out, err = io.StringIO(), io.StringIO()
    run = unittest.mock.Mock(side_effect=outcome) if isinstance(outcome, Exception) else None
    target = run or unittest.mock.Mock(return_value=outcome)
    with (
        unittest.mock.patch.object(cli, "run", target),
        contextlib.redirect_stdout(out),
        contextlib.redirect_stderr(err),
    ):
        code = cli.main(argv)
    return code, out.getvalue(), err.getvalue()


class CliTest(unittest.TestCase):
    """Output formats, argument handling, and exit codes."""

    def test_json(self) -> None:
        """--json prints the query and every hit's fields."""
        code, out, _ = call(["--json", "nix", "flakes"], HITS)
        self.assertEqual(code, 0)
        self.assertEqual(
            json.loads(out),
            {
                "query": "nix flakes",
                "hits": [
                    {"title": "NixOS", "url": "https://nixos.org/", "snippet": "Declarative."},
                    {"title": "Wiki", "url": "https://wiki.nixos.org/", "snippet": ""},
                ],
            },
        )

    def test_text(self) -> None:
        """Text output numbers the hits and omits empty snippets."""
        code, out, _ = call(["nix"], HITS)
        self.assertEqual(code, 0)
        self.assertEqual(
            out, "1. NixOS\nhttps://nixos.org/\nDeclarative.\n\n2. Wiki\nhttps://wiki.nixos.org/\n"
        )

    def test_arguments_reach_the_search(self) -> None:
        """Flags reach run, and -- lets a query start with a dash."""
        target = unittest.mock.Mock(return_value=[])
        with (
            unittest.mock.patch.object(cli, "run", target),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            cli.main(["--limit", "3", "--allow", "a.org", "--block", "b.org", "--", "-q"])
        target.assert_called_once_with("-q", allowed=["a.org"], blocked=["b.org"], limit=3)

    def test_exit_codes_carry_the_reason(self) -> None:
        """Each failure prints its message and exits with its own code."""
        cases: list[tuple[Exception, int]] = [
            (cookie.SessionError("no kagi_session cookie"), cli.SESSION_EXIT),
            (client.SignedOutError(), cli.SIGNED_OUT_EXIT),
            (client.ChallengeError(), cli.CHALLENGE_EXIT),
            (client.SearchError("Kagi answered HTTP 503"), cli.FAILURE_EXIT),
            (UnrecognizedPageError("Maintenance"), cli.FAILURE_EXIT),
        ]
        for error, expected in cases:
            with self.subTest(error=type(error).__name__):
                code, out, err = call(["x"], error)
                self.assertEqual(code, expected)
                self.assertEqual(out, "")
                self.assertEqual(err, f"kagi-search: {error}\n")
