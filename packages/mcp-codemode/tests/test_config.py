# Copyright (c) 2026 Bad3r

"""Tests for manifest parsing, override precedence, and secret reading."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from mcp_codemode.config import (
    DISABLE_ENV_VAR,
    ENABLE_ENV_VAR,
    PROJECT_CONFIG_NAME,
    ConfigError,
    SecretHeader,
    format_secret_header,
    load_manifest,
    make_alias,
    read_secret,
    resolve_enabled_servers,
    update_override_file,
    user_overrides_path,
)


class ConfigTest(unittest.TestCase):
    """Covers manifest loading, alias generation, overrides, and secret reading."""

    def test_make_alias(self) -> None:
        """Normalize server names into JS-safe identifiers."""
        self.assertEqual(make_alias("chrome-devtools"), "chrome_devtools")
        self.assertEqual(make_alias("google-developer-knowledge"), "google_developer_knowledge")
        self.assertEqual(make_alias("9server"), "_9server")

    def test_override_precedence(self) -> None:
        """Apply default < user < ancestor < project < env enablement precedence."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_dir = root / "state"
            ancestor = root / "work"
            project = ancestor / "app"
            project.mkdir(parents=True)

            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "client": "codex",
                        "servers": {
                            "alpha": {
                                "transport": "http",
                                "url": "https://example.invalid/a",
                                "enabled": True,
                            },
                            "google-developer-knowledge": {
                                "transport": "http",
                                "url": "https://example.invalid/gdk",
                                "enabled": False,
                            },
                            "beta": {
                                "transport": "stdio",
                                "command": "/bin/true",
                                "enabled": False,
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )
            manifest = load_manifest(manifest_path)

            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_dir)}, clear=False):
                os.environ.pop(ENABLE_ENV_VAR, None)
                os.environ.pop(DISABLE_ENV_VAR, None)

                states, sources = resolve_enabled_servers(manifest, project)
                self.assertEqual(
                    states,
                    {"alpha": True, "beta": False, "google-developer-knowledge": False},
                )
                self.assertEqual(sources["alpha"], "default")

                update_override_file(
                    user_overrides_path(),
                    enable_names=["google-developer-knowledge", "beta"],
                )
                states, sources = resolve_enabled_servers(manifest, project)
                self.assertTrue(states["google-developer-knowledge"])
                self.assertTrue(states["beta"])
                self.assertEqual(sources["beta"], str(user_overrides_path()))

                update_override_file(ancestor / PROJECT_CONFIG_NAME, disable_names=["beta"])
                update_override_file(project / PROJECT_CONFIG_NAME, enable_names=["beta"])
                states, sources = resolve_enabled_servers(manifest, project)
                self.assertTrue(states["beta"])
                self.assertEqual(sources["beta"], str(project / PROJECT_CONFIG_NAME))

                with mock.patch.dict(
                    os.environ,
                    {DISABLE_ENV_VAR: "google_developer_knowledge"},
                    clear=False,
                ):
                    states, sources = resolve_enabled_servers(manifest, project)
                    self.assertFalse(states["google-developer-knowledge"])
                    self.assertEqual(sources["google-developer-knowledge"], "env")

    def test_read_secret_and_errors(self) -> None:
        """Read trimmed secrets and reject missing or empty secret files."""
        with tempfile.TemporaryDirectory() as tmp:
            data_dir = Path(tmp)
            secret = SecretHeader(
                name="X-Goog-Api-Key",
                relative_path="google-developer-knowledge/api-key",
            )
            with mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(data_dir)}, clear=False):
                with self.assertRaises(ConfigError):
                    read_secret(secret)

                target = data_dir / secret.relative_path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("\r\n", encoding="utf-8")
                with self.assertRaises(ConfigError):
                    read_secret(secret)

                target.write_text("dummy-value\r\n", encoding="utf-8")
                self.assertEqual(read_secret(secret), "dummy-value")
                bearer = SecretHeader(
                    name="Authorization",
                    relative_path="cloudflare/api-key",
                    prefix="Bearer ",
                )
                cf_target = data_dir / bearer.relative_path
                cf_target.parent.mkdir(parents=True, exist_ok=True)
                cf_target.write_text("dummy-value\n", encoding="utf-8")
                self.assertEqual(format_secret_header(bearer), "Bearer dummy-value")

    def test_secret_header_prefix_validation(self) -> None:
        """Parse optional secretHeader.prefix and reject non-string or newline values."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            valid_manifest = root / "valid.json"
            valid_manifest.write_text(
                json.dumps(
                    {
                        "client": "claude",
                        "servers": {
                            "cloudflare-api": {
                                "transport": "http",
                                "url": "https://mcp.cloudflare.com/mcp",
                                "secretHeader": {
                                    "name": "Authorization",
                                    "prefix": "Bearer ",
                                    "relativePath": "cloudflare/api-key",
                                },
                            },
                            "gdk": {
                                "transport": "http",
                                "url": "https://example.invalid/mcp",
                                "secretHeader": {
                                    "name": "X-Goog-Api-Key",
                                    "relativePath": "gdk/api-key",
                                },
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )
            loaded = load_manifest(valid_manifest)
            cf_secret = loaded.servers["cloudflare-api"].secret_header
            gdk_secret = loaded.servers["gdk"].secret_header
            self.assertIsNotNone(cf_secret)
            self.assertIsNotNone(gdk_secret)
            if cf_secret is not None:
                self.assertEqual(cf_secret.prefix, "Bearer ")
            if gdk_secret is not None:
                self.assertEqual(gdk_secret.prefix, "")

            for bad_prefix in (123, "Bearer \n"):
                bad_manifest = root / "bad.json"
                bad_manifest.write_text(
                    json.dumps(
                        {
                            "client": "claude",
                            "servers": {
                                "cloudflare-api": {
                                    "transport": "http",
                                    "url": "https://mcp.cloudflare.com/mcp",
                                    "secretHeader": {
                                        "name": "Authorization",
                                        "prefix": bad_prefix,
                                        "relativePath": "cloudflare/api-key",
                                    },
                                }
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                with self.assertRaises(ConfigError):
                    load_manifest(bad_manifest)
