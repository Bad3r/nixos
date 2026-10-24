# Copyright (c) 2026 Bad3r
"""Argument handling of the sbx command line."""

import unittest

from sbx.cli import build_parser, split_command


class CommandLineTest(unittest.TestCase):
    """The guest command never reaches option parsing."""

    def test_split(self) -> None:
        """Options after the sandbox name stay sbx's; everything after -- is the command."""
        leading, command = split_command(["exec", "a", "--agent", "--", "sh", "-c", "x", "--", "y"])
        self.assertEqual(command, ["sh", "-c", "x", "--", "y"])
        args = build_parser().parse_args(leading)
        self.assertTrue(args.agent)
        self.assertEqual(split_command(["list", "--json"]), (["list", "--json"], []))

    def test_run_flags(self) -> None:
        """Repeated --in and --out flags of run accumulate."""
        leading, _ = split_command(["run", "nixos", "--in", "a", "--in", "b", "--out", "c", "--"])
        args = build_parser().parse_args(leading)
        self.assertEqual((args.inputs, args.outputs), (["a", "b"], ["c"]))
