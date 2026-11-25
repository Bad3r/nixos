# Copyright (c) 2026 Bad3r

"""Manifest loading, dynamic opt-in override resolution, and secret file reading."""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import threading
from dataclasses import dataclass, field
from pathlib import Path

from ._util import as_dict, as_list, parse_positive_timeout

USER_OVERRIDES_RELPATH = Path("mcp-codemode") / "overrides.json"
ENABLE_ENV_VAR = "MCP_CODEMODE_ENABLE"
DISABLE_ENV_VAR = "MCP_CODEMODE_DISABLE"
DEFAULT_TIMEOUT_SEC = 60.0
DEFAULT_TOOL_TIMEOUT_SEC = 180.0
OVERRIDES_FILE_MODE = 0o600


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
    def invalid_secret_path(cls, detail: str) -> ConfigError:
        """Create an error when a secret path is unsafe."""
        return cls(f"invalid MCP secret path: {detail}")

    @classmethod
    def unreadable_secret(cls, path: Path, detail: str) -> ConfigError:
        """Create an error when a secret file cannot be read."""
        return cls(f"failed to read MCP secret from {path}: {detail}")

    @classmethod
    def empty_secret(cls, path: Path) -> ConfigError:
        """Create an error when a secret file is empty."""
        return cls(f"MCP secret file is empty: {path}")

    @classmethod
    def invalid_timeout(cls) -> ConfigError:
        """Create an error for a non-positive or non-finite CLI timeout."""
        return cls("invalid timeout: --timeout must be a positive finite number")

    @classmethod
    def unknown_server(cls, server: str, manifest_path: Path) -> ConfigError:
        """Create an error when a CLI toggle names a server missing from a manifest."""
        return cls(f"unknown server '{server}' in manifest {manifest_path}")

    @classmethod
    def gateway_server_list(cls, path: Path, detail: str) -> ConfigError:
        """Create an error for a CLI toggle rejected by the gateway server list."""
        return cls(f"{detail} (gateway server list {path})")


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


def _xdg_home(env_var: str, fallback_leaf: str) -> Path:
    raw = os.environ.get(env_var, "")
    if raw:
        candidate = Path(raw)
        if candidate.is_absolute() and ".." not in candidate.parts:
            return candidate
    return Path.home() / ".local" / fallback_leaf


def xdg_data_home() -> Path:
    """Return XDG_DATA_HOME or ~/.local/share."""
    return _xdg_home("XDG_DATA_HOME", "share")


def xdg_state_home() -> Path:
    """Return XDG_STATE_HOME or ~/.local/state."""
    return _xdg_home("XDG_STATE_HOME", "state")


def user_overrides_path() -> Path:
    """Return the path to the user-level runtime override file."""
    return xdg_state_home() / USER_OVERRIDES_RELPATH


def _validate_relative_secret_path(rel_path: str) -> str | None:
    if not rel_path:
        return "secretHeader.relativePath must be non-empty"
    candidate = Path(rel_path)
    if candidate.is_absolute() or ".." in candidate.parts:
        return "secretHeader.relativePath must stay inside XDG_DATA_HOME"
    return None


def _lexical_child(base: Path, rel_path: str) -> Path:
    # Use normpath (not resolve) because sops-nix links ~/.local/share secrets into /run/user.
    return Path(os.path.normpath(Path(os.path.normpath(base)) / rel_path))


def _resolve_secret_path(secret_header: SecretHeader) -> Path:
    invalid_detail = _validate_relative_secret_path(secret_header.relative_path)
    if invalid_detail is not None:
        raise ConfigError.invalid_secret_path(invalid_detail)

    primary = _lexical_child(xdg_data_home(), secret_header.relative_path)
    if primary.exists():
        return primary

    # Fall back to ~/.local/share when a client sets a custom XDG_DATA_HOME while
    # Home Manager sops-nix rendered the secret into the default location.
    default_share = Path.home() / ".local" / "share"
    fallback = _lexical_child(default_share, secret_header.relative_path)
    if fallback != primary and fallback.exists():
        return fallback
    return primary


def read_secret(secret_header: SecretHeader) -> str:
    """Read and trim an API key without exposing its value in errors."""
    path = _resolve_secret_path(secret_header)
    try:
        value = path.read_text(encoding="utf-8").replace("\r", "").replace("\n", "")
    except (OSError, UnicodeDecodeError) as exc:
        detail = exc.strerror if isinstance(exc, OSError) and exc.strerror else str(exc)
        raise ConfigError.unreadable_secret(path, detail) from None
    if not value:
        raise ConfigError.empty_secret(path)
    return value


def format_secret_header(secret_header: SecretHeader) -> str:
    """Format an HTTP header value by prepending any configured prefix to the secret."""
    return f"{secret_header.prefix}{read_secret(secret_header)}"


def _parse_secret_header(name: str, raw_secret: object, path: Path) -> SecretHeader | None:
    if raw_secret is None:
        return None
    secret_dict = as_dict(raw_secret)
    if secret_dict is None:
        raise ConfigError.invalid_manifest(path, f"server '{name}' has invalid 'secretHeader'")
    header_name = secret_dict.get("name")
    rel_path = secret_dict.get("relativePath")
    raw_prefix = secret_dict.get("prefix", "")
    if (
        not isinstance(header_name, str)
        or not header_name
        or "\r" in header_name
        or "\n" in header_name
    ):
        raise ConfigError.invalid_manifest(path, f"server '{name}' has invalid 'secretHeader.name'")
    if not isinstance(rel_path, str):
        raise ConfigError.invalid_manifest(
            path, f"server '{name}' has invalid 'secretHeader.relativePath'"
        )
    rel_error = _validate_relative_secret_path(rel_path)
    if rel_error is not None:
        raise ConfigError.invalid_manifest(path, f"server '{name}' {rel_error}")
    if not isinstance(raw_prefix, str) or "\r" in raw_prefix or "\n" in raw_prefix:
        raise ConfigError.invalid_manifest(
            path, f"server '{name}' has invalid 'secretHeader.prefix'"
        )
    return SecretHeader(name=header_name, relative_path=rel_path, prefix=raw_prefix)


def _parse_manifest_timeout(
    raw: dict[str, object],
    field_name: str,
    default: float,
    server_name: str,
    path: Path,
) -> float:
    if field_name not in raw or raw[field_name] is None:
        return default
    parsed = parse_positive_timeout(raw[field_name])
    if parsed is None:
        raise ConfigError.invalid_manifest(
            path, f"server '{server_name}' has invalid '{field_name}'"
        )
    return parsed


def _parse_server_spec(name: str, raw: dict[str, object], path: Path) -> ServerSpec:
    transport = raw.get("transport")
    if transport not in ("stdio", "http"):
        raise ConfigError.invalid_manifest(
            path, f"server '{name}' has invalid transport {transport!r}"
        )

    enabled_raw = raw.get("enabled", True)
    if not isinstance(enabled_raw, bool):
        raise ConfigError.invalid_manifest(path, f"server '{name}' field 'enabled' must be boolean")

    url = raw.get("url")
    command = raw.get("command")
    if transport == "http" and (not isinstance(url, str) or not url):
        raise ConfigError.invalid_manifest(path, f"HTTP server '{name}' requires non-empty 'url'")
    if transport == "stdio" and (not isinstance(command, str) or not command):
        raise ConfigError.invalid_manifest(
            path, f"stdio server '{name}' requires non-empty 'command'"
        )

    secret_header = _parse_secret_header(name, raw.get("secretHeader"), path)
    args_list = as_list(raw.get("args"))
    args = tuple(str(item) for item in args_list) if args_list is not None else ()
    env_dict = as_dict(raw.get("env"))
    env = {k: str(v) for k, v in env_dict.items()} if env_dict is not None else {}

    startup_timeout = _parse_manifest_timeout(
        raw, "startupTimeoutSec", DEFAULT_TIMEOUT_SEC, name, path
    )
    tool_timeout = _parse_manifest_timeout(
        raw, "toolTimeoutSec", DEFAULT_TOOL_TIMEOUT_SEC, name, path
    )

    return ServerSpec(
        name=name,
        alias=make_alias(name),
        transport=str(transport),
        enabled_by_default=enabled_raw,
        primary_use=str(raw.get("primaryUse", "")),
        access_notes=str(raw.get("accessNotes", "")),
        url=url if isinstance(url, str) else None,
        command=command if isinstance(command, str) else None,
        args=args,
        env=env,
        secret_header=secret_header,
        startup_timeout_sec=startup_timeout,
        tool_timeout_sec=tool_timeout,
    )


def load_manifest(path: Path) -> Manifest:
    """Load and validate a compiled Code Mode manifest JSON file."""
    try:
        parsed: object = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConfigError.invalid_manifest(path, str(exc)) from None

    root = as_dict(parsed)
    servers_obj = as_dict(root.get("servers")) if root is not None else None
    if root is None or servers_obj is None:
        raise ConfigError.invalid_manifest(path, "expected object with 'servers' map")

    client = str(root.get("client", "unknown"))
    servers: dict[str, ServerSpec] = {}
    alias_to_name: dict[str, str] = {}
    for name, entry in sorted(servers_obj.items()):
        entry_dict = as_dict(entry)
        if entry_dict is None:
            raise ConfigError.invalid_manifest(path, f"server '{name}' must be an object")
        spec = _parse_server_spec(name, entry_dict, path)
        existing = alias_to_name.get(spec.alias)
        if existing is not None:
            raise ConfigError.invalid_manifest(
                path,
                f"server '{spec.name}' alias '{spec.alias}' collides with '{existing}'",
            )
        servers[spec.name] = spec
        alias_to_name[spec.alias] = spec.name

    return Manifest(client=client, servers=servers, alias_to_name=alias_to_name)


type OverridePair = tuple[list[str], list[str]]


def _parse_override_pair(data: dict[str, object], path: Path, scope: str) -> OverridePair:
    enable_list = as_list(data.get("enable", []))
    disable_list = as_list(data.get("disable", []))
    if (
        enable_list is None
        or disable_list is None
        or not all(isinstance(item, str) for item in enable_list)
        or not all(isinstance(item, str) for item in disable_list)
    ):
        raise ConfigError.invalid_override(
            path, f"{scope}: 'enable' and 'disable' must be arrays of strings"
        )
    return [item for item in enable_list if isinstance(item, str)], [
        item for item in disable_list if isinstance(item, str)
    ]


def _normalize_project_key(proj_dir: str) -> str:
    candidate = Path(proj_dir)
    if candidate.exists():
        return os.path.normpath(str(candidate.resolve()))
    return os.path.normpath(proj_dir)


def _read_override_file(path: Path) -> tuple[list[str], list[str], dict[str, OverridePair]]:
    if not path.is_file():
        return [], [], {}
    try:
        parsed: object = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConfigError.invalid_override(path, str(exc)) from None
    data = as_dict(parsed)
    if data is None:
        raise ConfigError.invalid_override(path, "expected JSON object")
    user_enable, user_disable = _parse_override_pair(data, path, "user")

    projects: dict[str, OverridePair] = {}
    raw_projects = data.get("projects")
    if raw_projects is not None:
        projects_dict = as_dict(raw_projects)
        if projects_dict is None:
            raise ConfigError.invalid_override(path, "'projects' must be an object")
        for proj_dir, entry in projects_dict.items():
            entry_dict = as_dict(entry)
            if entry_dict is None:
                raise ConfigError.invalid_override(
                    path, f"project entry '{proj_dir}' must be an object"
                )
            norm_dir = _normalize_project_key(proj_dir)
            projects[norm_dir] = _parse_override_pair(entry_dict, path, f"project '{proj_dir}'")

    return user_enable, user_disable, projects


def _discard_matching_aliases(names: set[str], target: str) -> None:
    target_alias = make_alias(target)
    stale = [item for item in names if item == target or make_alias(item) == target_alias]
    for item in stale:
        names.discard(item)


def _apply_toggle_names(
    existing: OverridePair,
    *,
    enable_names: list[str] | None,
    disable_names: list[str] | None,
) -> OverridePair:
    enable_set = set(existing[0])
    disable_set = set(existing[1])
    for name in enable_names or []:
        _discard_matching_aliases(enable_set, name)
        _discard_matching_aliases(disable_set, name)
        enable_set.add(name)
    for name in disable_names or []:
        _discard_matching_aliases(enable_set, name)
        _discard_matching_aliases(disable_set, name)
        disable_set.add(name)
    return sorted(enable_set), sorted(disable_set)


def _write_private_atomic(path: Path, content: str) -> None:
    tmp_path = path.with_suffix(f".tmp.{os.getpid()}.{threading.get_ident()}")
    fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, OVERRIDES_FILE_MODE)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        tmp_path.replace(path)
    except Exception:
        with contextlib.suppress(OSError):
            tmp_path.unlink()
        raise


def update_override_file(
    path: Path,
    *,
    enable_names: list[str] | None = None,
    disable_names: list[str] | None = None,
    project_dir: Path | None = None,
) -> OverridePair:
    """Serialize and atomically update user or project-scoped overrides inside overrides.json."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(f".{path.name}.lock")
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            user_enable, user_disable, projects = _read_override_file(path)

            if project_dir is None:
                updated = _apply_toggle_names(
                    (user_enable, user_disable),
                    enable_names=enable_names,
                    disable_names=disable_names,
                )
                user_enable, user_disable = updated
            else:
                proj_key = os.path.normpath(str(project_dir.resolve()))
                updated = _apply_toggle_names(
                    projects.get(proj_key, ([], [])),
                    enable_names=enable_names,
                    disable_names=disable_names,
                )
                if updated[0] or updated[1]:
                    projects[proj_key] = updated
                else:
                    projects.pop(proj_key, None)

            payload: dict[str, object] = {}
            if user_enable:
                payload["enable"] = user_enable
            if user_disable:
                payload["disable"] = user_disable
            if projects:
                payload["projects"] = {
                    proj_key: {
                        **({"enable": p_en} if p_en else {}),
                        **({"disable": p_dis} if p_dis else {}),
                    }
                    for proj_key, (p_en, p_dis) in sorted(projects.items())
                    if p_en or p_dis
                }

            _write_private_atomic(path, json.dumps(payload, indent=2) + "\n")
            return updated
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def _matching_project_entries(
    projects: dict[str, OverridePair],
    cwd: Path,
) -> list[tuple[str, OverridePair]]:
    resolved = cwd.resolve()
    matched: list[tuple[str, OverridePair]] = []
    for parent in reversed([resolved, *resolved.parents]):
        key = os.path.normpath(str(parent))
        pair = projects.get(key)
        if pair is not None:
            matched.append((key, pair))
    return matched


def read_override_summary(cwd: Path) -> dict[str, object]:
    """Return structured override and environment toggle state for bare `status` output."""
    user_path = user_overrides_path()
    project_dir = cwd.resolve()
    user_enable, user_disable, projects = _read_override_file(user_path)
    matching = [
        {"dir": key, "enable": pair[0], "disable": pair[1]}
        for key, pair in _matching_project_entries(projects, project_dir)
    ]
    return {
        "userOverrides": str(user_path),
        "userOverridesExists": user_path.is_file(),
        "userEnable": user_enable,
        "userDisable": user_disable,
        "projectDir": str(project_dir),
        "projectOverrideEntries": matching,
        "envEnable": sorted(_split_env_list(ENABLE_ENV_VAR)),
        "envDisable": sorted(_split_env_list(DISABLE_ENV_VAR)),
    }


def _split_env_list(var_name: str) -> set[str]:
    raw = os.environ.get(var_name, "")
    return {item.strip() for item in raw.split(",") if item.strip()}


def _apply_override_layer(
    manifest: Manifest,
    outcomes: tuple[dict[str, bool], dict[str, str]],
    pair: OverridePair,
    label: str,
) -> None:
    state, source = outcomes
    for item in pair[0]:
        resolved_name = manifest.resolve_name(item)
        if resolved_name is not None:
            state[resolved_name] = True
            source[resolved_name] = label
    for item in pair[1]:
        resolved_name = manifest.resolve_name(item)
        if resolved_name is not None:
            state[resolved_name] = False
            source[resolved_name] = label


def _apply_file_overrides(
    manifest: Manifest,
    outcomes: tuple[dict[str, bool], dict[str, str]],
    user_path: Path,
    cwd: Path,
) -> None:
    if not user_path.is_file():
        return
    u_en, u_dis, projects = _read_override_file(user_path)
    if u_en or u_dis:
        _apply_override_layer(manifest, outcomes, (u_en, u_dis), str(user_path))
    for proj_key, entry in _matching_project_entries(projects, cwd):
        _apply_override_layer(manifest, outcomes, entry, f"{user_path} ({proj_key})")


def resolve_enabled_servers(
    manifest: Manifest,
    cwd: Path | None = None,
) -> tuple[dict[str, bool], dict[str, str]]:
    """Compute effective enablement and provenance for each server.

    Precedence (lowest to highest):
    1. Manifest default (`enabled` boolean)
    2. User runtime overrides (`$XDG_STATE_HOME/mcp-codemode/overrides.json`)
    3. Project-scoped entries in `$XDG_STATE_HOME/mcp-codemode/overrides.json`
       (outermost ancestor to `cwd`)
    4. Process environment (`MCP_CODEMODE_ENABLE` / `MCP_CODEMODE_DISABLE`)
    """
    state: dict[str, bool] = {}
    source: dict[str, str] = {}

    for name, spec in manifest.servers.items():
        state[name] = spec.enabled_by_default
        source[name] = "default"

    outcomes = (state, source)
    _apply_file_overrides(
        manifest,
        outcomes,
        user_overrides_path(),
        cwd if cwd is not None else Path.cwd(),
    )

    env_en = _split_env_list(ENABLE_ENV_VAR)
    env_dis = _split_env_list(DISABLE_ENV_VAR)
    if env_en or env_dis:
        _apply_override_layer(manifest, outcomes, (list(env_en), list(env_dis)), "env")

    return state, source
