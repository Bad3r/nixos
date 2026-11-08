# Copyright (c) 2026 Bad3r
"""Command line output and exit codes."""

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

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
    """Output formats, argument handling, exit codes, and the failure log."""

    def setUp(self) -> None:
        """Keep the failure log in a throwaway state directory."""
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        env = unittest.mock.patch.dict(os.environ, {"XDG_STATE_HOME": state.name})
        env.start()
        self.addCleanup(env.stop)
        self.log = Path(state.name) / "kagi-search" / "kagi-search.log"

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

    def test_failures_are_logged_with_their_reason(self) -> None:
        """Every failure appends the query and reason to a private log."""
        call(["nix", "flakes"], client.SignedOutError())
        call(["x"], client.SearchError("Kagi answered HTTP 503"))
        lines = self.log.read_text().splitlines()
        self.assertIn("search 'nix flakes' failed: SignedOutError", lines[0])
        self.assertTrue(any("Kagi answered HTTP 503" in line for line in lines))
        self.assertEqual(self.log.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.log.parent.stat().st_mode & 0o777, 0o700)

    def test_an_unexpected_error_exits_with_the_failure_code(self) -> None:
        """A bug prints one line and exits 6; its traceback goes only to the log."""
        code, out, err = call(["x"], KeyError("hits"))
        self.assertEqual((code, out, err), (cli.FAILURE_EXIT, "", "kagi-search: 'hits'\n"))
        self.assertIn("Traceback (most recent call last)", self.log.read_text())

    def test_a_search_with_hits_logs_nothing(self) -> None:
        """Successful searches leave no log behind."""
        call(["x"], HITS)
        self.assertFalse(self.log.exists())

    def test_an_unwritable_log_keeps_the_exit_code(self) -> None:
        """A log that cannot be written does not change the outcome."""
        self.log.parent.write_text("not a directory")
        code, _, err = call(["x"], client.ChallengeError())
        self.assertEqual(code, cli.CHALLENGE_EXIT)
        self.assertTrue(err.startswith("kagi-search: "))

    def test_a_multiline_reason_prints_one_line(self) -> None:
        """A reason spanning lines reaches stderr as one line."""
        _, _, err = call(["x"], cookie.SessionError("profiles.ini:\n\tbad line"))
        self.assertEqual(err, "kagi-search: profiles.ini: bad line\n")

    def test_an_output_failure_is_reported_and_logged(self) -> None:
        """A failure while printing the hits exits 6 and is logged."""
        out = io.TextIOWrapper(io.BytesIO(), encoding="ascii")
        err = io.StringIO()
        hits = [Hit("\u00e9", "https://x.org/", "")]
        with (
            unittest.mock.patch.object(cli, "run", unittest.mock.Mock(return_value=hits)),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
        ):
            code = cli.main(["x"])
        self.assertEqual(code, cli.FAILURE_EXIT)
        self.assertIn("UnicodeEncodeError", self.log.read_text())

    def test_known_failures_log_no_traceback(self) -> None:
        """Only unexpected errors carry a traceback in the log."""
        call(["x"], client.SearchError("Kagi answered HTTP 503"))
        self.assertNotIn("Traceback", self.log.read_text())

    def test_a_closed_pipe_is_logged_without_a_shutdown_error(self) -> None:
        """Hits written to a closed pipe exit 6, are logged, and leave nothing for exit."""
        script = (
            "import sys, unittest.mock\n"
            "from kagi_search import cli\n"
            "from kagi_search.page import Hit\n"
            "hits = [Hit('a', 'https://a.org/', '')]\n"
            "with unittest.mock.patch.object(cli, 'run', return_value=hits):\n"
            "    sys.exit(cli.main(['x']))\n"
        )
        read, write = os.pipe()
        os.close(read)
        root = Path(__file__).resolve().parent.parent
        done = subprocess.run(
            [sys.executable, "-c", script],
            stdout=write,
            stderr=subprocess.PIPE,
            env={**os.environ, "PYTHONPATH": str(root)},
            check=False,
        )
        os.close(write)
        self.assertEqual(done.returncode, cli.FAILURE_EXIT)
        self.assertEqual(done.stderr.decode().count("\n"), 1)
        self.assertIn("BrokenPipeError", self.log.read_text())
