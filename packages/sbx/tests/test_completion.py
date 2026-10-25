# Copyright (c) 2026 Bad3r
"""Shell completion through the CLI entry point and argcomplete's real parser."""

import argparse
import contextlib
import dataclasses
import io
import json
import os
import shlex
import sys
from unittest import mock

from argcomplete.completers import SuppressCompleter
from argcomplete.finders import CompletionFinder
from sbx import cli, completion, windows
from sbx.config import Paths
from sbx.errors import SbxError
from sbx.model import FLAVOURS

from . import test_core


class CompletionTest(test_core.Fixture):
    """Tab reads local candidates without dispatching an sbx operation."""

    def complete(self, line: str, point: int | None = None) -> list[str]:
        """Run the completion protocol, replacing only its process exit and output fd."""
        output, stdout, stderr = io.StringIO(), io.StringIO(), io.StringIO()
        finder = CompletionFinder()

        def find(parser: argparse.ArgumentParser, **kwargs: object) -> None:
            finder(
                parser,
                always_complete_options=bool(kwargs["always_complete_options"]),
                default_completer=SuppressCompleter(),
                exit_method=sys.exit,
                output_stream=output,
            )

        environment = {
            "_ARGCOMPLETE": "1",
            "_ARGCOMPLETE_IFS": "\n",
            "_ARGCOMPLETE_SHELL": "bash",
            "_ARGCOMPLETE_SUPPRESS_SPACE": "1",
            "_ARGCOMPLETE_COMP_WORDBREAKS": "=:",
            "COMP_LINE": line,
            "COMP_POINT": str(len(line) if point is None else point),
        }
        with (
            mock.patch.dict(os.environ, environment),
            mock.patch.object(completion.argcomplete, "autocomplete", side_effect=find),
            mock.patch.object(Paths, "from_environment", return_value=self.paths),
            mock.patch.object(completion.Settings, "load", return_value=self.settings),
            mock.patch.object(cli.ops, "invoke") as dispatch,
            mock.patch.object(cli.ops.journal, "record") as record,
            contextlib.redirect_stdout(stdout),
            contextlib.redirect_stderr(stderr),
            self.assertRaises(SystemExit) as exit_status,
        ):
            cli.main(self.scratch / "settings.json", [])
        self.assertEqual(exit_status.exception.code, 0)
        self.assertEqual((stdout.getvalue(), stderr.getvalue()), ("", ""))
        dispatch.assert_not_called()
        record.assert_not_called()
        return output.getvalue().splitlines()

    def test_commands_and_options(self) -> None:
        """Nested commands, flags, and enum values come from the CLI parser."""
        for line, expected in (
            ("sbx cr", ["create"]),
            ("sbx base ", ["list", "build", "prepare"]),
            ("sbx --json share ", ["attach", "detach"]),
            ("sbx run nixos --ti", ["--timeout"]),
            ("sbx create nixos --net ", ["none", "egress"]),
            ("sbx create nixos --net=e", ["egress"]),
            ("sbx base build ", ["nixos", "nixos-gui"]),
        ):
            with self.subTest(line=line):
                self.assertCountEqual(self.complete(line), expected)
        self.assertIn("--help", self.complete("sbx --"))

    def test_local_bases_and_names(self) -> None:
        """Names exclude symlinks and reserved directories; bases include configured Windows."""
        for name in ("probe", "gui", "bases", ".queue", "invalid_name"):
            self.paths.root.joinpath(name).mkdir(parents=True, exist_ok=True)
        (self.paths.root / "alias").symlink_to(self.paths.root / "probe", target_is_directory=True)
        (self.paths.root / "not-a-directory").write_text("")
        self.settings = dataclasses.replace(
            self.settings,
            windows=windows.WindowsSettings("/firmware", 4096, {"win11": self.scratch}, "sbx-base"),
        )
        self.assertCountEqual(self.complete("sbx info "), ["probe", "gui"])
        self.assertCountEqual(
            self.complete("sbx create "), ["nixos", "nixos-gui", "debian-13", "win11"]
        )
        self.assertEqual(self.complete("sbx base prepare "), ["debian-13"])
        self.assertEqual(self.complete("sbx exec pr"), ["probe"])

    def test_unconfigured_bases(self) -> None:
        """The bare package offers Nix bases without treating missing configuration as a crash."""
        settings_path = self.scratch / "unconfigured.json"
        settings_path.write_text("{}")
        parser = cli.build_parser()
        action = argparse.Action([], "base")
        for kind, expected in (("bases", list(FLAVOURS)), ("cloud", [])):
            with self.subTest(kind=kind):
                completer = completion.LocalCompleter(kind, settings_path)
                self.assertEqual(
                    completer(
                        prefix="", action=action, parser=parser, parsed_args=argparse.Namespace()
                    ),
                    expected,
                )
        completer = completion.LocalCompleter("bases", settings_path)
        with (
            mock.patch.object(
                completion.Settings, "load", side_effect=SbxError("bad settings", code="internal")
            ),
            self.assertRaises(SbxError),
        ):
            completer(prefix="", action=action, parser=parser, parsed_args=argparse.Namespace())

    def test_copy_and_host_paths(self) -> None:
        """Copy endpoints select the opposite side, and host paths preserve spaces."""
        self.paths.root.joinpath("probe").mkdir(parents=True)
        file = self.scratch / "report file.txt"
        file.write_text("report")
        directory = self.scratch / "results"
        directory.mkdir()
        self.assertIn("probe:", self.complete("sbx cp pr"))
        self.assertEqual(self.complete(f"sbx cp {shlex.quote(str(file))} "), ["probe:"])
        self.assertEqual(self.complete("sbx cp probe:/root/file pr"), [])
        self.assertEqual(
            self.complete(f"sbx cp probe:/root/file {self.scratch}/report"),
            [str(file).replace(" ", "\\ ")],
        )
        self.assertEqual(self.complete("sbx cp probe:/root/"), [])
        self.assertEqual(
            self.complete(f"sbx run nixos --in {self.scratch}/report"),
            [str(file).replace(" ", "\\ ")],
        )
        self.assertEqual(
            self.complete(f"sbx run nixos --to {self.scratch}/res"), [str(directory) + "/"]
        )
        with contextlib.chdir(self.scratch):
            self.assertEqual(self.complete("sbx run nixos --in ./report"), ["./report\\ file.txt"])
        with mock.patch.dict(os.environ, {"HOME": str(self.scratch)}):
            self.assertEqual(self.complete("sbx run nixos --in ~/report"), ["~/report\\ file.txt"])

    def test_guest_arguments_and_free_text(self) -> None:
        """Guest commands and paths never receive host flags or file completions."""
        for line in (
            "sbx exec probe -- ",
            "sbx exec probe -- command --ti",
            "sbx run nixos -- --net ",
            "sbx run nixos --out ",
            "sbx type probe ",
            "sbx create --name ",
        ):
            with self.subTest(line=line):
                self.assertEqual(self.complete(line), [])

    def test_copy_colon_host_paths(self) -> None:
        """Colons in explicit host paths preserve file and opposite-endpoint completion."""
        self.paths.root.joinpath("probe").mkdir(parents=True)
        directory = self.scratch / "logs:old"
        directory.mkdir()
        (directory / "a.txt").write_text("report")
        with contextlib.chdir(self.scratch):
            self.assertEqual(self.complete("sbx cp ./logs:old/a.txt "), ["probe:"])
            self.assertEqual(self.complete("sbx cp ./logs:old/a"), ["old/a.txt"])
            self.assertEqual(self.complete("sbx cp probe:/root/file ./logs:old/a"), ["old/a.txt"])
        self.assertEqual(self.complete(f"sbx cp {directory}/a"), ["old/a.txt"])

    def test_shares_and_key_chords(self) -> None:
        """Shares follow local policy and key chords keep their modifier prefix."""
        policy = self.scratch / "grants.json"
        policy.write_text(json.dumps({"sandboxShares": {"source": {"hostPath": "/srv/source"}}}))
        with mock.patch.object(completion.shares, "POLICY", policy):
            self.assertCountEqual(self.complete("sbx share attach probe "), ["shared", "source"])
        self.assertIn("ctrl+alt+t", self.complete("sbx key probe ctrl+alt+"))

    def test_cursor_position(self) -> None:
        """Arguments beyond the cursor do not change the current completion context."""
        line = "sbx run nixos --ti -- echo done"
        self.assertEqual(self.complete(line, len("sbx run nixos --ti")), ["--timeout"])
