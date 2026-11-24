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
                    self.assertEqual(bare["projectOverrides"], [str(proj_dir.resolve())])
                    self.assertTrue(bare["projectOverridesExist"])

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
