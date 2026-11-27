# Herdr

Two Herdr programs have app modules:

- `herdr` is the terminal workspace manager, declared in [its app module](../../../modules/apps/herdr.nix).
- `herdr-app` is the desktop window, declared in [its app module](../../../modules/apps/herdr-app.nix).

`herdr-app` runs its terminals in the `herdr-core` server that ships in its package.
The `hc` command of `herdr-core` is not installed system-wide.

Run `herdr` to start or reattach terminal workspaces.
Set additional TOML fields through `programs.herdr.extended.settings`; its `theme` keys override the managed theme.

## Theme

The managed `[theme.custom]` table sets every Herdr palette token from the Stylix scheme and the VS Code Dark 2026 colors in [the shared palette](../../../modules/stylix/_vscode-dark-2026.nix), with the accent, blue, and teal tokens desaturated.
The sidebar and tab bar use the terminal's default background (`reset`), so they share Kitty's translucency, and the sidebar edge is the faint `surface_dim` separator; popups use the same background inside their accent border.
Herdr has no theme files and applies these overrides over any selected built-in theme, so the theme picker in Settings has no visible effect.
Run `herdr server reload-config` after switching to apply palette changes to a running server.

## Agent integrations

Antigravity CLI, Claude Code, and Codex report sessions to Herdr through hooks in [the shared hook registry](../../../modules/agents/hooks/herdr-agent-session.nix).
Those hooks run the integration scripts directly from the pinned Herdr source.
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

## herdr-app privacy

`herdr-app` keeps a daily usage report with an install id, the agents, layouts, mods, and commands used, and bucketed counts and durations.
The report also names the OS, architecture, app and core versions, error events, and customization flags.
The launcher sets `HERDR_TELEMETRY=0`, which stops the report and deletes `~/.config/herdr-app/telemetry/`.
Settings keeps its usage-data switch and states that `HERDR_TELEMETRY` turned it off.

Report uploads, feedback sending, and update checks run only in release builds.
The package builds from source.
The llm-agents fork limits release-note clip downloads from `media.herdr.dev` to release builds as well.
Leave `HERDR_RELEASES_URL` unset, because it turns hourly update checks back on.
User-written mods can still load images from URLs and run commands.

The package appends its `herdr-core` to PATH, which keeps the app from running the core installer.
A `herdr-core` earlier on PATH takes precedence.
`herdr-core` contains no telemetry and contacts `releases.herdr.dev` only for `hc update` and remote machine installs.
It asks logind to enable linger on each start.
The polkit policy in [the polkit module](../../../modules/security/polkit.nix) refuses that request.
The core therefore stops when the last session of the owner ends.

<https://herdr.dev/docs/configuration/>
