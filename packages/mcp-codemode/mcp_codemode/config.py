# Copyright (c) 2026 Bad3r

"""Manifest loading, dynamic opt-in override resolution, and secret file reading."""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import cast

PROJECT_CONFIG_NAME = ".mcp-codemode.json"
USER_OVERRIDES_RELPATH = Path("mcp-codemode") / "overrides.json"
ENABLE_ENV_VAR = "MCP_CODEMODE_ENABLE"
DISABLE_ENV_VAR = "MCP_CODEMODE_DISABLE"
DEFAULT_TIMEOUT_SEC = 60.0
DEFAULT_TOOL_TIMEOUT_SEC = 180.0


class ConfigError(RuntimeError):
    """Raised when manifest, override, or secret files are invalid or unreadable."""

    @classmethod
    def invalid_manifest(cls, path: Path, detail: str) -> ConfigError:
        """Create an error for malformed manifest files."""
        return cls(f"invalid manifest {path}: {detail}")

    @classmethod
    def invalid_override(cls, path: Path, detail: str) -> ConfigError:
        """Create an error for malformed override files."""
        return cls(f"invalid override file {path}: {detail}")

    @classmethod
    def unreadable_secret(cls, path: Path, detail: str) -> ConfigError:
        """Create an error when a secret file cannot be read."""
        return cls(f"failed to read MCP secret from {path}: {detail}")

    @classmethod
    def empty_secret(cls, path: Path) -> ConfigError:
        """Create an error when a secret file is empty."""
        return cls(f"MCP secret file is empty: {path}")


@dataclass(frozen=True)
class SecretHeader:
    """Reference to an HTTP header value stored under XDG_DATA_HOME."""

    name: str
    relative_path: str
    prefix: str = ""


@dataclass(frozen=True)
class ServerSpec:
    """Normalized configuration for one upstream MCP server."""

    name: str
    alias: str
    transport: str
    enabled_by_default: bool = True
    primary_use: str = ""
    access_notes: str = ""
    url: str | None = None
    command: str | None = None
    args: tuple[str, ...] = ()
    env: dict[str, str] = field(default_factory=dict[str, str])
    env_vars: tuple[str, ...] = ()
    secret_header: SecretHeader | None = None
    startup_timeout_sec: float = DEFAULT_TIMEOUT_SEC
    tool_timeout_sec: float = DEFAULT_TOOL_TIMEOUT_SEC


@dataclass(frozen=True)
class Manifest:
    """Compiled Code Mode manifest for a client."""

    client: str
    servers: dict[str, ServerSpec]
    alias_to_name: dict[str, str]

    def resolve_name(self, name_or_alias: str) -> str | None:
        """Resolve an exact server name or identifier-safe alias to canonical name."""
        if name_or_alias in self.servers:
            return name_or_alias
        return self.alias_to_name.get(name_or_alias)


def make_alias(name: str) -> str:
    """Convert a server name such as 'chrome-devtools' to a JS identifier 'chrome_devtools'."""
    alias = re.sub(r"[^A-Za-z0-9_$]", "_", name)
    if not alias or alias[0].isdigit():
        alias = f"_{alias}"
    return alias


def xdg_data_home() -> Path:
    """Return XDG_DATA_HOME or ~/.local/share."""
    raw = os.environ.get("XDG_DATA_HOME")
    return Path(raw) if raw else Path.home() / ".local" / "share"


def xdg_state_home() -> Path:
    """Return XDG_STATE_HOME or ~/.local/state."""
    raw = os.environ.get("XDG_STATE_HOME")
    return Path(raw) if raw else Path.home() / ".local" / "state"


def user_overrides_path() -> Path:
    """Return the path to the user-level runtime override file."""
    return xdg_state_home() / USER_OVERRIDES_RELPATH


def read_secret(secret_header: SecretHeader) -> str:
    """Read and trim an API key from XDG_DATA_HOME without exposing its value in errors."""
    path = xdg_data_home() / secret_header.relative_path
    try:
        value = path.read_text(encoding="utf-8").replace("\r", "").replace("\n", "")
    except OSError as exc:
        raise ConfigError.unreadable_secret(path, exc.strerror or str(exc)) from None
    if not value:
        raise ConfigError.empty_secret(path)
    return value


def format_secret_header(secret_header: SecretHeader) -> str:
    """Format an HTTP header value by prepending any configured prefix to the secret."""
    return f"{secret_header.prefix}{read_secret(secret_header)}"


def _as_object_dict(value: object) -> dict[str, object] | None:
    if not isinstance(value, dict):
        return None
    raw_items = cast("dict[object, object]", value)
    return {str(k): v for k, v in raw_items.items()}


def _as_object_list(value: object) -> list[object] | None:
    if not isinstance(value, list):
        return None
    return list(cast("list[object]", value))


def _parse_secret_header(name: str, raw_secret: object, path: Path) -> SecretHeader | None:
    if raw_secret is None:
        return None
    secret_dict = _as_object_dict(raw_secret)
    if secret_dict is None:
        raise ConfigError.invalid_manifest(path, f"server '{name}' has invalid 'secretHeader'")
    header_name = secret_dict.get("name")
    rel_path = secret_dict.get("relativePath")
    raw_prefix = secret_dict.get("prefix", "")
    if not isinstance(header_name, str) or not isinstance(rel_path, str):
        raise ConfigError.invalid_manifest(path, f"server '{name}' has invalid 'secretHeader'")
    if not isinstance(raw_prefix, str) or "\r" in raw_prefix or "\n" in raw_prefix:
        raise ConfigError.invalid_manifest(
            path, f"server '{name}' has invalid 'secretHeader.prefix'"
        )
    return SecretHeader(name=header_name, relative_path=rel_path, prefix=raw_prefix)


def _parse_server_spec(name: str, raw: dict[str, object], path: Path) -> ServerSpec:
    transport = raw.get("transport")
    if transport not in ("stdio", "http"):
        raise ConfigError.invalid_manifest(
            path, f"server '{name}' has invalid transport {transport!r}"
        )

    url = raw.get("url")
    command = raw.get("command")
    if transport == "http" and (not isinstance(url, str) or not url):
        raise ConfigError.invalid_manifest(path, f"HTTP server '{name}' requires non-empty 'url'")
    if transport == "stdio" and (not isinstance(command, str) or not command):
        raise ConfigError.invalid_manifest(
            path, f"stdio server '{name}' requires non-empty 'command'"
        )

    secret_header = _parse_secret_header(name, raw.get("secretHeader"), path)
    args_list = _as_object_list(raw.get("args"))
    args = tuple(str(item) for item in args_list) if args_list is not None else ()
    env_dict = _as_object_dict(raw.get("env"))
    env = {k: str(v) for k, v in env_dict.items()} if env_dict is not None else {}
    env_vars_list = _as_object_list(raw.get("envVars"))
    env_vars = tuple(str(item) for item in env_vars_list) if env_vars_list is not None else ()

    startup_raw = raw.get("startupTimeoutSec", DEFAULT_TIMEOUT_SEC)
    tool_raw = raw.get("toolTimeoutSec", DEFAULT_TOOL_TIMEOUT_SEC)
    startup_timeout = (
        float(startup_raw) if isinstance(startup_raw, (int, float)) else DEFAULT_TIMEOUT_SEC
    )
    tool_timeout = (
        float(tool_raw) if isinstance(tool_raw, (int, float)) else DEFAULT_TOOL_TIMEOUT_SEC
    )

    return ServerSpec(
        name=name,
        alias=make_alias(name),
        transport=str(transport),
        enabled_by_default=bool(raw.get("enabled", True)),
        primary_use=str(raw.get("primaryUse", "")),
        access_notes=str(raw.get("accessNotes", "")),
        url=url if isinstance(url, str) else None,
        command=command if isinstance(command, str) else None,
        args=args,
        env=env,
        env_vars=env_vars,
        secret_header=secret_header,
        startup_timeout_sec=startup_timeout,
        tool_timeout_sec=tool_timeout,
    )


def load_manifest(path: Path) -> Manifest:
    """Load and validate a compiled Code Mode manifest JSON file."""
    try:
        parsed: object = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigError.invalid_manifest(path, str(exc)) from None

    root = _as_object_dict(parsed)
    servers_obj = _as_object_dict(root.get("servers")) if root is not None else None
    if root is None or servers_obj is None:
        raise ConfigError.invalid_manifest(path, "expected object with 'servers' map")

    client = str(root.get("client", "unknown"))
    servers: dict[str, ServerSpec] = {}
    alias_to_name: dict[str, str] = {}
    for name, entry in sorted(servers_obj.items()):
        entry_dict = _as_object_dict(entry)
        if entry_dict is None:
            raise ConfigError.invalid_manifest(path, f"server '{name}' must be an object")
        spec = _parse_server_spec(name, entry_dict, path)
        servers[spec.name] = spec
        alias_to_name[spec.alias] = spec.name

    return Manifest(client=client, servers=servers, alias_to_name=alias_to_name)


def _read_override_file(path: Path) -> tuple[list[str], list[str]]:
    if not path.is_file():
        return [], []
    try:
        parsed: object = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigError.invalid_override(path, str(exc)) from None
    data = _as_object_dict(parsed)
    if data is None:
        raise ConfigError.invalid_override(path, "expected JSON object")
    enable_raw = data.get("enable", [])
    disable_raw = data.get("disable", [])
    enable_list = _as_object_list(enable_raw)
    disable_list = _as_object_list(disable_raw)
    if enable_list is None or disable_list is None:
        raise ConfigError.invalid_override(path, "'enable' and 'disable' must be arrays of strings")
    return [str(x) for x in enable_list], [str(x) for x in disable_list]


def update_override_file(
    path: Path,
    *,
    enable_names: list[str] | None = None,
    disable_names: list[str] | None = None,
) -> tuple[list[str], list[str]]:
    """Atomically update an override JSON file to enable or disable named servers."""
    existing_enable, existing_disable = _read_override_file(path)
    enable_set = set(existing_enable)
    disable_set = set(existing_disable)

    for name in enable_names or []:
        enable_set.add(name)
        disable_set.discard(name)
    for name in disable_names or []:
        disable_set.add(name)
        enable_set.discard(name)

    sorted_enable = sorted(enable_set)
    sorted_disable = sorted(disable_set)

    payload: dict[str, list[str]] = {}
    if sorted_enable:
        payload["enable"] = sorted_enable
    if sorted_disable:
        payload["disable"] = sorted_disable

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(f".tmp.{os.getpid()}")
    tmp_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(path)
    return sorted_enable, sorted_disable


def find_project_overrides(cwd: Path) -> list[Path]:
    """Walk from filesystem root down to cwd collecting .mcp-codemode.json files."""
    resolved = cwd.resolve()
    candidates = [resolved, *resolved.parents]
    return [
        parent / PROJECT_CONFIG_NAME
        for parent in reversed(candidates)
        if (parent / PROJECT_CONFIG_NAME).is_file()
    ]


def _split_env_list(var_name: str) -> set[str]:
    raw = os.environ.get(var_name, "")
    return {item.strip() for item in raw.split(",") if item.strip()}


def resolve_enabled_servers(
    manifest: Manifest,
    cwd: Path | None = None,
) -> tuple[dict[str, bool], dict[str, str]]:
    """Compute effective enablement and provenance for each server.

    Precedence (lowest to highest):
    1. Manifest default (`enabled` boolean)
    2. User runtime overrides (`$XDG_STATE_HOME/mcp-codemode/overrides.json`)
    3. Project `.mcp-codemode.json` files (outermost ancestor to `cwd`)
    4. Process environment (`MCP_CODEMODE_ENABLE` / `MCP_CODEMODE_DISABLE`)
    """
    state: dict[str, bool] = {}
    source: dict[str, str] = {}

    for name, spec in manifest.servers.items():
        state[name] = spec.enabled_by_default
        source[name] = "default"

    def apply_layer(enable: set[str], disable: set[str], label: str) -> None:
        for item in enable:
            resolved_name = manifest.resolve_name(item)
            if resolved_name is not None:
                state[resolved_name] = True
                source[resolved_name] = label
        for item in disable:
            resolved_name = manifest.resolve_name(item)
            if resolved_name is not None:
                state[resolved_name] = False
                source[resolved_name] = label

    user_path = user_overrides_path()
    if user_path.is_file():
        u_en, u_dis = _read_override_file(user_path)
        apply_layer(set(u_en), set(u_dis), str(user_path))

    work_dir = cwd if cwd is not None else Path.cwd()
    for proj_path in find_project_overrides(work_dir):
        p_en, p_dis = _read_override_file(proj_path)
        apply_layer(set(p_en), set(p_dis), str(proj_path))

    env_en = _split_env_list(ENABLE_ENV_VAR)
    env_dis = _split_env_list(DISABLE_ENV_VAR)
    if env_en or env_dis:
        apply_layer(env_en, env_dis, "env")

    return state, source
