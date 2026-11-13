# Herdr

Run `herdr` to start or reattach terminal workspaces.
The package and managed configuration are declared in [the app module](../../../modules/apps/herdr.nix).
Set additional TOML fields through `programs.herdr.extended.settings`; its `theme` keys override the managed theme.

## Theme

The managed `[theme.custom]` table sets every Herdr palette token from the Stylix scheme and the VS Code Dark 2026 colors in [the shared palette](../../../modules/stylix/_vscode-dark-2026.nix), with the accent, blue, and teal tokens desaturated.
The sidebar and tab bar use the terminal's default background (`reset`), so they share Kitty's translucency, and the sidebar edge is the faint `surface_dim` separator; popups use the same background inside their accent border.
Herdr has no theme files and applies these overrides over any selected built-in theme, so the theme picker in Settings has no visible effect.
Run `herdr server reload-config` after switching to apply palette changes to a running server.

## Agent integrations

Claude Code and Codex report sessions to Herdr through `SessionStart` hooks in [the shared hook registry](../../../modules/agents/hooks/herdr-agent-session.nix), which run the integration scripts from the pinned Herdr source.
The app module links the same scripts where `herdr integration status` looks for them, so `herdr integration install` fails for these agents instead of adding a second hook.
Integrations for other agents remain unmanaged.

## Configuration and privacy

Home Manager owns the configuration file, so change settings declaratively instead of using Herdr's configuration editor.
The managed configuration sets `onboarding = false`, because the first-run setup saves its choices into that file, and sends background notifications through the outer terminal (`ui.toast.delivery = "terminal"`).
Preserve an existing unmanaged configuration before activating the module.
Keep credentials out of module settings because generated files enter the Nix store.

The managed configuration disables background release and agent-detection manifest requests.
Bundled agent detection remains available; detection fixes arrive with package updates.
Explicit updates, remote installation, plugins, hooks, and coding agents can still make network requests.
An alternative configuration selected through `HERDR_CONFIG_PATH` bypasses the managed settings.
The launcher disables diagnostic log events through `HERDR_LOG`.
Herdr can still create empty log files and stores session state, including workspace and terminal information.

The source review covers the pinned Herdr CLI, without establishing privacy guarantees for plugins or child processes.
Recheck outbound request paths when updating the package.

<https://herdr.dev/docs/configuration/>
