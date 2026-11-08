# Herdr

Run `herdr` to start or reattach terminal workspaces.
The package and managed configuration are declared in [the app module](../../../modules/apps/herdr.nix).
Set additional TOML fields through `programs.herdr.extended.settings`.

## Configuration and privacy

Home Manager owns the configuration file, so change settings declaratively instead of using Herdr's configuration editor.
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
