# Copyright (c) 2026 Bad3r
"""Argument handling of the sbx command line."""

import contextlib
import io
import json
import unittest
from pathlib import Path
from unittest import mock

from sbx.cli import build_parser, main, split_command
from sbx.errors import SbxError


class CommandLineTest(unittest.TestCase):
    """The guest command never reaches option parsing."""

    def test_no_arguments_prints_help(self) -> None:
        """A bare invocation succeeds without settings, services, or journal writes."""
        output, errors = io.StringIO(), io.StringIO()
        with (
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(errors),
            mock.patch("sbx.cli.Settings.load") as load,
            mock.patch("sbx.cli.journal.record") as record,
        ):
            self.assertEqual(main(Path("/missing/settings.json"), []), 0)
        self.assertIn("usage: sbx", output.getvalue())
        self.assertIn("start a sandbox", output.getvalue())
        self.assertEqual(errors.getvalue(), "")
        load.assert_not_called()
        record.assert_not_called()

    def test_missing_verb_with_json_is_still_an_error(self) -> None:
        """An incomplete JSON command retains its machine-readable usage error."""
        output = io.StringIO()
        with contextlib.redirect_stdout(output), mock.patch("sbx.cli.journal.record"):
            self.assertEqual(main(Path("/missing/settings.json"), ["--json"]), 2)
        self.assertEqual(json.loads(output.getvalue())["error"]["code"], "usage")

    def test_split(self) -> None:
        """Options after the sandbox name stay sbx's; everything after -- is the command."""
        leading, command = split_command(
            ["exec", "a", "--timeout", "1m", "--", "sh", "-c", "x", "--"]
        )
        self.assertEqual(command, ["sh", "-c", "x", "--"])
        args = build_parser().parse_args(leading)
        self.assertEqual(args.timeout, "1m")
        self.assertEqual(split_command(["list", "--json"]), (["list", "--json"], []))

    def test_run_flags(self) -> None:
        """Repeated --in and --out flags of run accumulate."""
        leading, _ = split_command(["run", "nixos", "--in", "a", "--in", "b", "--out", "c", "--"])
        args = build_parser().parse_args(leading)
        self.assertEqual((args.inputs, args.outputs), (["a", "b"], ["c"]))

    def test_net_flag(self) -> None:
        """--net defaults to none, takes egress, and rejects anything else."""
        parser = build_parser()
        self.assertEqual(parser.parse_args(["create", "nixos"]).net, "none")
        self.assertEqual(parser.parse_args(["run", "nixos", "--net", "egress"]).net, "egress")
        with self.assertRaises(SbxError) as refused:
            parser.parse_args(["create", "nixos", "--net", "lan"])
        self.assertEqual(refused.exception.code, "usage")

    def test_input_and_base_verbs(self) -> None:
        """Chords for key, one text for type, one image for base prepare, and --gui parse."""
        parser = build_parser()
        self.assertEqual(
            parser.parse_args(["key", "g", "ctrl+c", "enter"]).keys, ["ctrl+c", "enter"]
        )
        self.assertEqual(parser.parse_args(["type", "g", "--json", "ls -l"]).text, "ls -l")
        self.assertEqual(parser.parse_args(["base", "prepare", "debian-13"]).image, "debian-13")
        self.assertTrue(parser.parse_args(["create", "nixos", "--gui"]).gui)
        self.assertFalse(parser.parse_args(["run", "nixos"]).gui)
        for argv in (["key", "g"], ["type", "g"], ["type", "g", "a", "b"]):
            with self.subTest(argv=argv), self.assertRaises(SbxError):
                parser.parse_args(argv)
