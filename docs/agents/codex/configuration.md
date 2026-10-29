# Codex configuration

Edit the Nix sources before rebuilding Home Manager.
The launcher regenerates `$CODEX_HOME/config.toml` when its input files change.
Edits made directly to that output can disappear on the next merge.

## Choose the owning file

- [Settings catalog](../../../modules/agents/codex/_default-settings.nix): optional settings and their types.
- [Site policy](../../../modules/agents/codex/_settings.nix): model selection, permissions, memory, terminal preferences, and MCP composition.
- [Feature flags](../../../modules/agents/codex/_features.nix): active flags and commented alternatives from the Rust feature registry.
- [Process environment](../../../modules/agents/codex/_env.nix): environment values exported by login sessions and the Codex launcher.
- [Shared MCP registry](../../../modules/agents/mcp/servers.nix): server endpoints, commands, and client membership.
- [Execution policy](../../../modules/agents/codex/_exec-policy.nix): command approval rules and the controlled shell.

Uncomment an optional setting and supply its value to configure it.
Site policy overrides catalog values.
Keep credentials in runtime secrets or Codex's login store because Nix configuration becomes readable in the store.

## Desktop application

The [ChatGPT app module](../../../modules/apps/chatgpt.nix) installs OpenAI's Linux desktop application from the pinned `llm-agents` input.
Use `programs.chatgpt.extended.enable` to control installation and `programs.chatgpt.extended.package` to select its package.
The [shared app catalog](../../../modules/hosts/common/apps-enable.nix) owns its default enablement.
After rebuilding and switching NixOS, launch the application from the desktop menu or run `chatgpt`.
Sign in with a ChatGPT account and choose ChatGPT or Codex in the application.
The `codex` command continues to launch the separately configured terminal agent.

The application is an Electron build named `Codex`, so its Chromium profile lives in `$XDG_CONFIG_HOME/Codex`.
That directory holds window state, cookies, caches, and the built-in browser profile.
Its agent sessions, history, and memories go to `$CODEX_HOME`, shared with the terminal agent.
Configure both through `$CODEX_HOME`; the capitalized directory carries no Codex settings.

## Runtime files

The [launcher](../../../modules/agents/codex/_wrapper.nix) merges these files in order:

1. `$CODEX_HOME/config.base.toml`, generated from Nix settings.
2. `$CODEX_HOME/projects.nix.toml`, generated from declared project trust.
3. `$CODEX_HOME/trusted-projects.toml`, mutable user project trust.
4. `$CODEX_HOME/overrides.toml`, optional mutable settings that override the preceding inputs.

Add project trust to the mutable input so it survives regeneration.
Changes to that input take effect on the next launch.
Configuring the shell tool's environment uses `shell_environment_policy`; launch environment values affect the Codex process itself.

After a rebuild and switch, launch Codex again to merge the new base settings.
Login-session environment changes also require a new login.
Commit attribution policy belongs in agent instructions.

The launcher executes the pinned Codex package directly so daemon startup and code mode use its package manifest and bundled helpers.
Eligible interactive launches use the shared local background server by default.
Use `codex --no-daemon` to run a session without it.

## Approval defaults and runtime overrides

The [site policy](../../../modules/agents/codex/_settings.nix) selects the default approval reviewer.
The automatic reviewer evaluates requests for additional permissions and commands that execution rules mark for review.

To use human approval by default, create or edit `$CODEX_HOME/overrides.toml` (normally `~/.config/codex/overrides.toml`):

```toml
approvals_reviewer = "user"
```

The override takes effect on the next launch without rebuilding or switching.
It survives regeneration of the managed configuration.
Remove the entry to restore the managed default.
Invalid TOML stops the launcher and reports the input file.

For one launch, use `codex -c 'approvals_reviewer="user"'`.
Use `codex --approve-for-me` to explicitly select automatic review for one launch.
The `/permissions` picker changes the active session without rebuilding.
Regeneration can replace choices saved by Codex to `config.toml`.
Use `overrides.toml` for a persistent default.

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

Use the [local Codex mirror](../../reference/local-mirrors.md) when a setting is undocumented or a documented option disagrees with the installed binary.
Inspect `ConfigToml`, `RawMcpServerConfig`, and the `FEATURES` registry for accepted fields, transport inference, and removed flags.
The environment catalog names the Rust readers for each variable.
Compare the installed version with the pinned package before copying options from a newer source revision.

[Upstream configuration reference](https://developers.openai.com/codex/config-reference/)
