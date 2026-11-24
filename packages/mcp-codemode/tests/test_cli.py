# Copyright (c) 2026 Bad3r

"""Tests for mcp-codemode CLI commands (enable, disable, status)."""

from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from typing import cast
from unittest import mock

from mcp_codemode.cli import main
from mcp_codemode.config import PROJECT_CONFIG_NAME, user_overrides_path


class CliTest(unittest.TestCase):
    """Covers enable, disable, --user, and status --json."""

    def test_enable_disable_and_status(self) -> None:
        """Toggle project/user overrides and emit accurate status JSON."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_dir = root / "state"
            proj_dir = root / "proj"
            proj_dir.mkdir()
            manifest_path = root / "manifest.json"
            manifest_path.write_text(
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

            old_cwd = Path.cwd()
            os.chdir(proj_dir)
            try:
                with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_dir)}, clear=False):
                    self.assertEqual(main(["enable", "google-developer-knowledge"]), 0)
                    self.assertTrue((proj_dir / PROJECT_CONFIG_NAME).is_file())

                    self.assertEqual(main(["disable", "--user", "deepwiki"]), 0)
                    self.assertTrue(user_overrides_path().is_file())

                    buf = io.StringIO()
                    with redirect_stdout(buf):
                        rc = main(["status", "--manifest", str(manifest_path), "--json"])
                    self.assertEqual(rc, 0)
                    status = cast("dict[str, object]", json.loads(buf.getvalue()))
                    rows = cast("list[dict[str, object]]", status["servers"])
                    by_name = {str(row["name"]): row for row in rows}
                    self.assertTrue(by_name["google-developer-knowledge"]["enabled"])
                    self.assertFalse(by_name["deepwiki"]["enabled"])
            finally:
                os.chdir(old_cwd)
