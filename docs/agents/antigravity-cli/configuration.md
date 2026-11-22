# Antigravity CLI and Hub configuration

Edit the Nix modules before rebuilding Home Manager.
Activation merges declared keys into `~/.gemini/config/` and `~/.gemini/antigravity-cli/settings.json` while keeping runtime state intact.

## Choose the owning file

- [CLI module](../../../modules/agents/antigravity-cli/nixos.nix): wraps `agy` with the controlled shell and registers `antigravity-cli` plugin options.
- [Hub module](../../../modules/apps/antigravity-hub/nixos.nix): wraps `antigravity` with the controlled shell and sets the Hub server port.
- [Telemetry policy](../../../modules/agents/antigravity-cli/_telemetry.nix): disables Hub Language Server and `agy acp` telemetry, CLI auto-updates, `chrome-devtools-mcp` checks, and Hub update polling.
- [Controlled shell](../../../modules/agents/antigravity-cli/_shell.nix): runs `direnv`, exports per-conversation `TMPDIR`, and shims `rm` to trash.
- [Home Manager module](../../../modules/agents/antigravity-cli/home.nix): compiles instructions, skills, permissions, hooks, MCP servers, and plugin state.
- [Shared system prompt](../../../modules/agents/system-prompt.nix): renders `~/.gemini/config/AGENTS.md` with `ask_question` and `sbx` settings.
- [CLI settings](../../../modules/agents/antigravity-cli/_settings.nix): sets startup mode, sandbox flag, editor mode, notifications, and verbosity for `agy`.
- [Permissions policy](../../../modules/agents/antigravity-cli/_permissions.nix): defines `allow`, `ask`, and `deny` rules for CLI settings and Hub grants.
- [Activation merger](../../../modules/agents/antigravity-cli/_activation.nix): installs missing marketplace plugins and merges declared JSON keys atomically.
- [Shared plugin catalog](../../../modules/agents/_plugins.nix): sets default plugin enablement for `antigravity-cli`.
- [Shared MCP registry](../../../modules/agents/mcp/servers.nix): defines server endpoints, wrappers, and client membership compiled by [the MCP compiler](../../../modules/agents/mcp.nix).
- [Shared hook registry](../../../modules/agents/hooks.nix): generates `PreInvocation` session reporting and `PreToolUse` scratch validation.
- [Shared skill registry](../../../modules/agents/skills.nix): compiles standalone skills into `~/.gemini/config/skills/`.

## Shared and CLI-only files

`antigravity-cli` and `antigravity-hub` share `~/.gemini/config/` for `AGENTS.md`, `skills/`, `hooks.json`, `mcp_config.json`, and `config.json`.
Enabling `antigravity-hub` without `antigravity-cli` writes that shared root and `~/.config/Antigravity/app_storage.json` while leaving `~/.gemini/antigravity-cli/settings.json` untouched.
`~/.gemini/config/.nix-managed.json` tracks Nix-owned keys across all managed JSON targets.
Dropping a Nix declaration removes its tracked entry on the next switch while leaving user entries, model picks, and `installedFrom` metadata intact.
Activation also deletes leftover `migrated-settings` directories and manual `herdr` hook blocks that conflict with declarative ownership.

## Telemetry and update checks

`agy` accepts `--disable_telemetry` only on `acp`, so the wrapper injects it there and rejects falsy overrides before `--`.
Root `agy` sessions lack a local telemetry flag and read the Google account toggle from `/config` when signed in.
The `antigravity-cli/no-google-telemetry` check pins `agy` flag support against upstream `--help` output and checks Hub wrapper flags and environment.
`agy remote-control start` resolves the unwrapped store binary via `/proc/self/exe`, and Hub SSH windows run remote Language Server binaries.

## Plugins and MCP servers

Override plugins per host under `programs."antigravity-cli".extended.plugins`.
On activation, when `antigravity-cli` is enabled and Google endpoints respond, missing non-builtin plugins install via `agy plugin install`.
`plugins.<name>.enabled` then merges into `~/.gemini/config/config.json` without overwriting `.installedFrom`.
[The MCP compiler](../../../modules/agents/mcp.nix) writes remote servers under `serverUrl`, sets `timeoutSeconds` only past 180 seconds, and strips client-specific keys.

## Controlled shell and permissions

Both launchers prepend the controlled `bash` wrapper and `rm` trash shim to `PATH` and default `TMPDIR` to the agent scratch root.
Every wrapper call strips its own directory from `PATH` so nested `bash` calls reach the real shell.
It sets per-conversation `TMPDIR` from `ANTIGRAVITY_CONVERSATION_ID` and falls back to `/tmp` when the scratch root is unwritable inside a sandbox.
Permissions evaluate `action(target)` rules (`read_file`, `write_file`, `read_url`, `command`, `mcp`) with `deny > ask > allow` precedence.
Allowed `read_file`, `write_file`, and `read_url` targets also populate the Linux terminal sandbox mounts and outbound domain allowlist.

## Validation

Build the Antigravity activation, shell wrapper, and scratch-guard checks before switching:

```sh
nix build --accept-flake-config --no-link \
  'path:.#checks.x86_64-linux."antigravity-cli/activation-merge"' \
  'path:.#checks.x86_64-linux."antigravity-cli/no-google-telemetry"' \
  'path:.#checks.x86_64-linux."antigravity-cli/shell-wrapper"' \
  'path:.#checks.x86_64-linux."agents/hooks/scratch-guard"'
```

<https://antigravity.google/docs>
