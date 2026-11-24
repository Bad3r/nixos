# Copyright (c) 2026 Bad3r

"""Command-line interface for mcp-codemode (serve, status, enable, disable)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from ._paths import resolve_bwrap_bin, resolve_node_bin, resolve_sandbox_script
from .config import (
    PROJECT_CONFIG_NAME,
    ConfigError,
    load_manifest,
    resolve_enabled_servers,
    update_override_file,
    user_overrides_path,
)
from .sandbox import DEFAULT_EXEC_TIMEOUT_SEC
from .server import CodeModeServer, build_sandbox_config


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mcp-codemode",
        description="Local Code Mode MCP gateway and opt-in server toggle.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    serve_p = sub.add_parser("serve", help="Run the Code Mode MCP stdio server.")
    serve_p.add_argument(
        "--manifest", type=Path, required=True, help="Compiled client manifest JSON."
    )
    serve_p.add_argument(
        "--no-bwrap",
        action="store_true",
        help="Disable Bubblewrap confinement (for nested-sandbox tests only).",
    )
    serve_p.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_EXEC_TIMEOUT_SEC,
        help=f"Per-execution sandbox timeout in seconds (default: {DEFAULT_EXEC_TIMEOUT_SEC:.0f}).",
    )

    status_p = sub.add_parser("status", help="Show effective MCP server enablement.")
    status_p.add_argument("--manifest", type=Path, help="Compiled client manifest JSON.")
    status_p.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")

    enable_p = sub.add_parser("enable", help="Enable one or more opt-in MCP servers.")
    enable_p.add_argument(
        "--user", action="store_true", help="Write user-level override instead of project."
    )
    enable_p.add_argument("servers", nargs="+", help="Server name(s) or aliases to enable.")

    disable_p = sub.add_parser("disable", help="Disable one or more MCP servers.")
    disable_p.add_argument(
        "--user", action="store_true", help="Write user-level override instead of project."
    )
    disable_p.add_argument("servers", nargs="+", help="Server name(s) or aliases to disable.")

    return parser


def _cmd_serve(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    sandbox_config = build_sandbox_config(
        node_bin=resolve_node_bin(),
        bwrap_bin=resolve_bwrap_bin(),
        sandbox_script=resolve_sandbox_script(),
        use_bwrap=not args.no_bwrap,
        timeout_sec=args.timeout,
    )
    server = CodeModeServer(manifest, sandbox_config)
    return server.serve_stdio()


def _cmd_status(args: argparse.Namespace) -> int:
    cwd = Path.cwd()
    if args.manifest is not None:
        manifest = load_manifest(args.manifest)
        states, sources = resolve_enabled_servers(manifest, cwd)
        rows: list[dict[str, Any]] = [
            {
                "name": name,
                "alias": spec.alias,
                "transport": spec.transport,
                "enabled": states[name],
                "source": sources[name],
            }
            for name, spec in manifest.servers.items()
        ]
        if args.json:
            print(json.dumps({"client": manifest.client, "servers": rows}, indent=2))
        else:
            for row in rows:
                flag = "enabled" if row["enabled"] else "disabled"
                print(f"{row['name']}\t{flag}\t({row['source']})")
        return 0

    user_path = user_overrides_path()
    project_path = cwd / PROJECT_CONFIG_NAME
    payload = {
        "userOverrides": str(user_path),
        "userOverridesExists": user_path.is_file(),
        "projectConfig": str(project_path),
        "projectConfigExists": project_path.is_file(),
    }
    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        print(f"user overrides: {user_path} ({'present' if user_path.is_file() else 'absent'})")
        print(
            f"project config: {project_path} ({'present' if project_path.is_file() else 'absent'})"
        )
    return 0


def _cmd_toggle(args: argparse.Namespace, *, enable: bool) -> int:
    target = user_overrides_path() if args.user else Path.cwd() / PROJECT_CONFIG_NAME
    if enable:
        update_override_file(target, enable_names=list(args.servers))
    else:
        update_override_file(target, disable_names=list(args.servers))
    action = "enabled" if enable else "disabled"
    print(f"Updated {target}: {action} {', '.join(args.servers)}")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for mcp-codemode."""
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "serve":
            return _cmd_serve(args)
        if args.command == "status":
            return _cmd_status(args)
        if args.command == "enable":
            return _cmd_toggle(args, enable=True)
        if args.command == "disable":
            return _cmd_toggle(args, enable=False)
    except ConfigError as exc:
        sys.stderr.write(f"mcp-codemode: {exc}\n")
        return 1
    return 0
