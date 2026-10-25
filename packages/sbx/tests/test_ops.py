# Copyright (c) 2026 Bad3r
"""The operation registry behind the command line and the MCP tools."""

import argparse
import contextlib
import unittest
from typing import cast
from unittest import mock

from sbx import cli, mcp, ops
from sbx.errors import SbxError

from .test_mcp import samples

# Verbs for the owner's shell and host services, never for agents.
CLI_ONLY = frozenset({("base", "prepare"), ("sleep",), ("vsock", "serve"), ("vsock", "sync")})


def leaves(
    parser: argparse.ArgumentParser, path: tuple[str, ...] = ()
) -> list[tuple[tuple[str, ...], ops.Operation]]:
    """Return each verb the parser takes, with the operation it runs."""
    found: list[tuple[tuple[str, ...], ops.Operation]] = []
    for action in parser._actions:  # noqa: SLF001
        choices: object = action.choices
        if not isinstance(choices, dict):
            continue
        for name, child in cast("dict[str, object]", choices).items():
            if not isinstance(child, argparse.ArgumentParser):
                continue
            operation = child.get_default("operation")
            if operation is None:
                found.extend(leaves(child, (*path, name)))
            else:
                found.append(((*path, name), cast("ops.Operation", operation)))
    return found


class ExposureTest(unittest.TestCase):
    """Every verb is a tool unless it is explicitly the shell's alone."""

    def test_every_verb_is_a_tool_or_cli_only(self) -> None:
        """The parser runs each registry entry under its own path, in registry order."""
        verbs = leaves(cli.build_parser())
        self.assertEqual([path for path, _ in verbs], [op.path for op in ops.OPERATIONS])
        for path, operation in verbs:
            with self.subTest(path=path):
                self.assertEqual(operation.path, path)
                self.assertEqual(operation.mcp_exposed, path not in CLI_ONLY)
        self.assertEqual(
            [tool.name for tool in mcp.TOOLS],
            [op.name for op in ops.OPERATIONS if op.path not in CLI_ONLY],
        )

    def test_every_tool_argument_reaches_its_handler(self) -> None:
        """Each handler reads every argument its tool declares."""
        for tool in mcp.TOOLS:
            with self.subTest(tool=tool.name):
                args = mcp.parse_arguments(tool, samples(tool))
                # Later steps may fail on the mock's answers; the reads come first.
                with contextlib.suppress(Exception):
                    tool.handler(mock.MagicMock(), args, ops.Ctx(None))
                self.assertLessEqual({param.name for param in tool.params if param.mcp}, args.read)

    def test_undeclared_reads_fail(self) -> None:
        """A handler reading a parameter its operation lacks is an internal error."""
        args = ops.Args(ops.OPERATIONS_BY_NAME["info"], {"name": "a"})
        with self.assertRaises(SbxError) as raised:
            args.optional("image")
        self.assertEqual(raised.exception.code, "internal")


if __name__ == "__main__":
    unittest.main()
