# Codex configuration

Edit the Nix sources before rebuilding Home Manager.
The launcher regenerates `$CODEX_HOME/config.toml` when its input files change.
Edits made directly to that output can disappear on the next merge.

## Choose the owning file

- [Settings catalog](../../modules/agents/codex/_default-settings.nix): optional settings and their types.
- [Site policy](../../modules/agents/codex/_settings.nix): model selection, permissions, memory, terminal preferences, and MCP composition.
- [Feature flags](../../modules/agents/codex/_features.nix): active flags and commented alternatives from the Rust feature registry.
- [Process environment](../../modules/agents/codex/_env.nix): environment values exported by login sessions and the Codex launcher.
- [Shared MCP registry](../../modules/agents/mcp/servers.nix): server endpoints, commands, and client membership.
- [Execution policy](../../modules/agents/codex/_exec-policy.nix): command approval rules and the controlled shell.

Uncomment an optional setting and supply its value to configure it.
Site policy overrides catalog values.
Keep credentials in runtime secrets or Codex's login store because Nix configuration becomes readable in the store.

## Runtime files

The [launcher](../../modules/agents/codex/_wrapper.nix) merges these files in order:

1. `$CODEX_HOME/config.base.toml`, generated from Nix settings.
2. `$CODEX_HOME/projects.nix.toml`, generated from declared project trust.
3. `$CODEX_HOME/trusted-projects.toml`, mutable user project trust.

Add project trust to the mutable input so it survives regeneration.
Changes to that input take effect on the next launch.
Configuring the shell tool's environment uses `shell_environment_policy`; launch environment values affect the Codex process itself.

After a rebuild and switch, launch Codex again to merge the new base settings.
Login-session environment changes also require a new login.
Commit attribution policy belongs in agent instructions.

## Unrecognized settings

Run the installed parser without starting a model turn or connecting MCP servers:

```sh
codex --strict-config app-server --stdio < /dev/null
```

The command exits nonzero and names the first unknown field.
Fix its Nix producer, rebuild, and launch again.
Codex infers MCP transport from `command` or `url`; the shared registry compiles each client's representation separately.

Recognized feature flags can still be removed no-ops.
Desktop browser and computer-use gates belong to administrator requirements, which user config cannot override.
Inspect their runtime stage:

```sh
codex features list
```

The `codex/config` flake check validates generated TOML with the pinned binary, checks configured feature stages, and exercises both rejected fields.

## Check source behavior

Use the [local Codex mirror](../reference/local-mirrors.md) when a setting is undocumented or a documented option disagrees with the installed binary.
Inspect `ConfigToml`, `RawMcpServerConfig`, and the `FEATURES` registry for accepted fields, transport inference, and removed flags.
The environment catalog names the Rust readers for each variable.
Compare the installed version with the pinned package before copying options from a newer source revision.

[Upstream configuration reference](https://developers.openai.com/codex/config-reference/)
