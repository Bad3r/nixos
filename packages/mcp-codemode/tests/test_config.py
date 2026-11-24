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

                update_override_file(
                    user_overrides_path(),
                    project_dir=ancestor,
                    disable_names=["beta"],
                )
                update_override_file(
                    user_overrides_path(),
                    project_dir=project,
                    enable_names=["beta"],
                )
                # Untrusted repo files must not affect enablement.
                (project / ".mcp-codemode.json").write_text(
                    json.dumps({"disable": ["alpha", "beta", "google-developer-knowledge"]}),
                    encoding="utf-8",
                )
                states, sources = resolve_enabled_servers(manifest, project)
                self.assertTrue(states["alpha"])
                self.assertTrue(states["beta"])
                self.assertEqual(sources["beta"], f"{user_overrides_path()} ({project.resolve()})")

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

                # Sops-nix links ~/.local/share/<app>/api-key into /run/user/<uid>/secrets/...
                external_dir = Path(tmp) / "run_secrets"
                external_dir.mkdir(parents=True, exist_ok=True)
                external_secret = external_dir / "key"
                external_secret.write_text("symlinked-secret\n", encoding="utf-8")
                link_target = data_dir / "linked" / "api-key"
                link_target.parent.mkdir(parents=True, exist_ok=True)
                link_target.symlink_to(external_secret)
                linked_header = SecretHeader(name="X-Api-Key", relative_path="linked/api-key")
                self.assertEqual(read_secret(linked_header), "symlinked-secret")

                for bad_rel in ("/etc/passwd", "../escape", "sub/../../escape", ""):
                    with self.assertRaises(ConfigError):
                        read_secret(SecretHeader(name="X-Api-Key", relative_path=bad_rel))

    def test_secret_header_prefix_validation(self) -> None:
        """Parse optional secretHeader.prefix and reject unsafe headers or paths."""
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

            bad_headers: list[dict[str, object]] = [
                {"name": "Authorization", "prefix": 123, "relativePath": "cloudflare/api-key"},
                {
                    "name": "Authorization",
                    "prefix": "Bearer \n",
                    "relativePath": "cloudflare/api-key",
                },
                {"name": "", "relativePath": "cloudflare/api-key"},
                {"name": "X-Bad\r\nHeader", "relativePath": "cloudflare/api-key"},
                {"name": "Authorization", "relativePath": "/abs/secret"},
                {"name": "Authorization", "relativePath": "../escape"},
            ]
            for bad_header in bad_headers:
                bad_manifest = root / "bad.json"
                bad_manifest.write_text(
                    json.dumps(
                        {
                            "client": "claude",
                            "servers": {
                                "cloudflare-api": {
                                    "transport": "http",
                                    "url": "https://mcp.cloudflare.com/mcp",
                                    "secretHeader": bad_header,
                                }
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                with self.assertRaises(ConfigError):
                    load_manifest(bad_manifest)
