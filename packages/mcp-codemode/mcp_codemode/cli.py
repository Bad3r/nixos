# Copyright (c) 2026 Bad3r

"""Command-line interface for mcp-codemode (serve, status, enable, disable)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, cast

from ._paths import resolve_bwrap_bin, resolve_node_bin, resolve_sandbox_script
from ._util import parse_positive_timeout
from .config import (
    ConfigError,
    load_manifest,
    read_override_summary,
    resolve_enabled_servers,
    update_override_file,
    user_overrides_path,
)
from .sandbox import DEFAULT_EXEC_TIMEOUT_SEC, SandboxConfig
from .server import CodeModeServer


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

    for action_name, verb in (("enable", "Enable"), ("disable", "Disable")):
        toggle_p = sub.add_parser(action_name, help=f"{verb} one or more MCP servers.")
        toggle_p.add_argument(
            "--user",
            action="store_true",
            help="Write user-wide override instead of project-scoped override in user state.",
        )
        toggle_p.add_argument(
            "--manifest",
            type=Path,
            help="Optional client manifest JSON to validate and canonicalize server names.",
        )
        toggle_p.add_argument(
            "servers", nargs="+", help=f"Server name(s) or aliases to {action_name}."
        )

    return parser


def _cmd_serve(args: argparse.Namespace) -> int:
    timeout_sec = parse_positive_timeout(args.timeout)
    if timeout_sec is None:
        raise ConfigError.invalid_timeout()
    manifest = load_manifest(args.manifest)
    sandbox_config = SandboxConfig(
        node_bin=resolve_node_bin(),
        bwrap_bin=resolve_bwrap_bin(),
        sandbox_script=resolve_sandbox_script(),
        use_bwrap=not args.no_bwrap,
        timeout_sec=timeout_sec,
    )
    server = CodeModeServer(manifest, sandbox_config)
    return server.serve_stdio()


def _format_override_pair(enable: list[str], disable: list[str]) -> str:
    parts: list[str] = []
    if enable:
        parts.append(f"enable=[{', '.join(enable)}]")
    if disable:
        parts.append(f"disable=[{', '.join(disable)}]")
    return " ".join(parts) if parts else "none"


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

    payload = read_override_summary(cwd)
    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    user_en = cast("list[str]", payload["userEnable"])
    user_dis = cast("list[str]", payload["userDisable"])
    env_en = cast("list[str]", payload["envEnable"])
    env_dis = cast("list[str]", payload["envDisable"])
    entries = cast("list[dict[str, Any]]", payload["projectOverrideEntries"])

    state_label = "present" if payload["userOverridesExists"] else "absent"
    print(f"user overrides: {payload['userOverrides']} ({state_label})")
    print(f"  user toggles: {_format_override_pair(user_en, user_dis)}")
    if entries:
        for entry in entries:
            pair_str = _format_override_pair(
                cast("list[str]", entry["enable"]),
                cast("list[str]", entry["disable"]),
            )
            print(f"  project {entry['dir']}: {pair_str}")
    else:
        print(f"  project overrides for {payload['projectDir']}: none")
    print(f"  env toggles: {_format_override_pair(env_en, env_dis)}")
    print("pass --manifest <path> or run codemode.servers() to inspect per-server availability")
    return 0


def _resolve_toggle_names(raw_names: list[str], manifest_path: Path | None) -> list[str]:
    if manifest_path is None:
        return list(raw_names)
    manifest = load_manifest(manifest_path)
    resolved: list[str] = []
    for name in raw_names:
        canonical = manifest.resolve_name(name)
        if canonical is None:
            raise ConfigError.unknown_server(name, manifest_path)
        resolved.append(canonical)
    return resolved


def _cmd_toggle(args: argparse.Namespace, *, enable: bool) -> int:
    names = _resolve_toggle_names(list(args.servers), args.manifest)
    target = user_overrides_path()
    project_dir = None if args.user else Path.cwd().resolve()
    if enable:
        update_override_file(target, enable_names=names, project_dir=project_dir)
    else:
        update_override_file(target, disable_names=names, project_dir=project_dir)
    scope = "user" if project_dir is None else f"project {project_dir}"
    action = "enabled" if enable else "disabled"
    print(f"Updated {target} ({scope}): {action} {', '.join(names)}")
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
