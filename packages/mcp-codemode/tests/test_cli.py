# Copyright (c) 2026 Bad3r

"""Tests for mcp-codemode CLI commands (serve, enable, disable, status)."""

from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import cast
from unittest import mock

from mcp_codemode.cli import main
from mcp_codemode.config import (
    ENABLE_ENV_VAR,
    read_override_summary,
    user_overrides_path,
)


def _write_sample_manifest(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "client": "antigravity",
                "servers": {
                    "google-developer-knowledge": {
                        "transport": "http",
                        "url": "https://example.invalid/mcp",
                        "enabled": False,
                    },
                    "deepwiki": {
                        "transport": "http",
                        "url": "https://example.invalid/dw",
                        "enabled": True,
                    },
                },
            }
        ),
        encoding="utf-8",
    )


class CliTest(unittest.TestCase):
    """Covers enable, disable, alias normalization, bare/manifest status, and validation."""

    def setUp(self) -> None:
        """Isolate overrides and point the gateway server list at an absent per-test path."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.state_dir = Path(tmp.name) / "state"
        self.gateway_path = Path(tmp.name) / "servers.json"
        for patcher in (
            mock.patch("mcp_codemode.cli.GATEWAY_SERVERS_PATH", self.gateway_path),
            mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(self.state_dir)}, clear=False),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def _run(self, argv: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = main(argv)
        return rc, out.getvalue(), err.getvalue()

    def test_gateway_list_rejects_unknown_names(self) -> None:
        """Reject a typo against the gateway server list and write nothing."""
        self.gateway_path.write_text(
            json.dumps(["google-developer-knowledge", "deepwiki"]), encoding="utf-8"
        )
        for argv in (
            ["enable", "--user", "google-developer-knowlege"],
            ["disable", "--user", "deepwiki", "google-developer-knowlege"],
        ):
            rc, _, err = self._run(argv)
            self.assertEqual(rc, 1)
            self.assertIn("unknown server 'google-developer-knowlege'", err)
            self.assertIn(str(self.gateway_path), err)
        self.assertFalse(user_overrides_path().exists())

    def test_gateway_list_canonicalizes_aliases(self) -> None:
        """Store the listed name for an alias; --manifest validates on its own."""
        manifest_path = self.state_dir.parent / "manifest.json"
        _write_sample_manifest(manifest_path)
        self.gateway_path.write_text(json.dumps(["deepwiki"]), encoding="utf-8")
        rc, _, err = self._run(
            ["disable", "--user", "--manifest", str(manifest_path), "google-developer-knowledge"]
        )
        self.assertEqual((rc, err), (0, ""))

        self.gateway_path.write_text(
            json.dumps(["google-developer-knowledge", "deepwiki"]), encoding="utf-8"
        )
        rc, out, err = self._run(["enable", "--user", "google_developer_knowledge"])
        self.assertEqual((rc, err), (0, ""))
        self.assertIn("enabled google-developer-knowledge", out)
        summary = read_override_summary(Path.cwd())
        self.assertEqual(summary["userEnable"], ["google-developer-knowledge"])
        self.assertEqual(summary["userDisable"], [])

    def test_gateway_list_malformed_is_an_error(self) -> None:
        """Fail on unparsable or non-array gateway server lists instead of skipping them."""
        cases = {
            "{not json": "invalid JSON",
            json.dumps({"deepwiki": True}): "expected a JSON array of server names",
            json.dumps(["deepwiki", 3]): "expected a JSON array of server names",
            json.dumps(["deepwiki", ""]): "expected a JSON array of server names",
        }
        for content, expected in cases.items():
            with self.subTest(content=content):
                self.gateway_path.write_text(content, encoding="utf-8")
                rc, _, err = self._run(["enable", "--user", "deepwiki"])
                self.assertEqual(rc, 1)
                self.assertIn(expected, err)
                self.assertIn(str(self.gateway_path), err)
        self.assertFalse(user_overrides_path().exists())

    def test_absent_gateway_list_keeps_names_as_given(self) -> None:
        """Without a gateway server list or --manifest, store names unvalidated."""
        rc, _, err = self._run(["enable", "--user", "not-listed-anywhere"])
        self.assertEqual((rc, err), (0, ""))
        summary = read_override_summary(Path.cwd())
        self.assertEqual(summary["userEnable"], ["not-listed-anywhere"])

    def test_enable_disable_and_status(self) -> None:
        """Toggle project/user overrides, resolve mixed aliases, and emit status output."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_dir = root / "state"
            proj_dir = root / "proj"
            proj_dir.mkdir()
            manifest_path = root / "manifest.json"
            _write_sample_manifest(manifest_path)

            old_cwd = Path.cwd()
            os.chdir(proj_dir)
            try:
                with mock.patch.dict(
                    os.environ,
                    {"XDG_STATE_HOME": str(state_dir), ENABLE_ENV_VAR: "deepwiki"},
                    clear=False,
                ):
                    self.assertEqual(main(["disable", "google_developer_knowledge"]), 0)
                    self.assertEqual(main(["enable", "google-developer-knowledge"]), 0)
                    self.assertTrue(user_overrides_path().is_file())
                    self.assertFalse((proj_dir / ".mcp-codemode.json").exists())

                    self.assertEqual(main(["disable", "--user", "deepwiki"]), 0)

                    buf = io.StringIO()
                    with redirect_stdout(buf):
                        rc = main(["status", "--manifest", str(manifest_path), "--json"])
                    self.assertEqual(rc, 0)
                    status = cast("dict[str, object]", json.loads(buf.getvalue()))
                    rows = cast("list[dict[str, object]]", status["servers"])
                    by_name = {str(row["name"]): row for row in rows}
                    self.assertTrue(by_name["google-developer-knowledge"]["enabled"])
                    self.assertTrue(by_name["deepwiki"]["enabled"])

                    bare_json = io.StringIO()
                    with redirect_stdout(bare_json):
                        rc = main(["status", "--json"])
                    self.assertEqual(rc, 0)
                    bare = cast("dict[str, object]", json.loads(bare_json.getvalue()))
                    self.assertEqual(bare["userDisable"], ["deepwiki"])
                    self.assertEqual(bare["envEnable"], ["deepwiki"])
                    entries = cast("list[dict[str, object]]", bare["projectOverrideEntries"])
                    self.assertEqual([entry["dir"] for entry in entries], [str(proj_dir.resolve())])

                    bare_text = io.StringIO()
                    with redirect_stdout(bare_text):
                        rc = main(["status"])
                    self.assertEqual(rc, 0)
                    self.assertIn("google-developer-knowledge", bare_text.getvalue())
                    self.assertIn("--manifest", bare_text.getvalue())
            finally:
                os.chdir(old_cwd)

    def test_manifest_validation_and_invalid_timeout(self) -> None:
        """Reject unknown server names with --manifest and non-positive --timeout."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_dir = root / "state"
            manifest_path = root / "manifest.json"
            _write_sample_manifest(manifest_path)

            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_dir)}, clear=False):
                err = io.StringIO()
                with redirect_stderr(err):
                    rc = main(["enable", "--manifest", str(manifest_path), "nonexistent"])
                self.assertEqual(rc, 1)
                self.assertIn("unknown server", err.getvalue())

                out = io.StringIO()
                with redirect_stdout(out):
                    rc = main(
                        [
                            "enable",
                            "--user",
                            "--manifest",
                            str(manifest_path),
                            "google_developer_knowledge",
                        ]
                    )
                self.assertEqual(rc, 0)
                self.assertIn("google-developer-knowledge", out.getvalue())

                for bad_timeout in ("0", "-10", "nan"):
                    err = io.StringIO()
                    with redirect_stderr(err):
                        rc = main(
                            [
                                "serve",
                                "--manifest",
                                str(manifest_path),
                                "--timeout",
                                bad_timeout,
                            ]
                        )
                    self.assertEqual(rc, 1)
                    self.assertIn("invalid timeout", err.getvalue())
