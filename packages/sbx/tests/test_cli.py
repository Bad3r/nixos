# Copyright (c) 2026 Bad3r
"""Argument handling of the sbx command line."""

import unittest

from sbx.cli import build_parser, split_command
from sbx.core import SbxError


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

    def test_net_flag(self) -> None:
        """--net defaults to none, takes egress, and rejects anything else."""
        parser = build_parser()
        self.assertEqual(parser.parse_args(["create", "nixos"]).net, "none")
        self.assertEqual(parser.parse_args(["run", "nixos", "--net", "egress"]).net, "egress")
        with self.assertRaises(SbxError) as refused:
            parser.parse_args(["create", "nixos", "--net", "lan"])
        self.assertEqual(refused.exception.code, "usage")
