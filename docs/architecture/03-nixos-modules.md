# NixOS Modules

This document covers the system-level aggregator namespace and app registry helpers.

## The `flake.nixosModules` Namespace

All system modules feed into `flake.nixosModules` so that hosts compose features by name rather than by path.

```nix
# Structure
flake.nixosModules = {
  base = { ... };                    # Core system settings
  "system76-support" = { ... };      # Hardware support
  "hardware-lenovo-y27q-20" = { ... }; # Monitor profile
  apps = {
    steam = { ... };
    # ...
  };
  browsers = {
    firefox = { ... };
    # ...
  };
};
```

## App Registry

Per-app modules live under `flake.nixosModules.apps.<name>` and follow the pattern in [Apps Module Style Guide](../guides/apps-module-style-guide.md).

Browsers are the exception: they live under `flake.nixosModules.browsers.<name>` from `modules/browsers/<name>/apps.nix`, with Home Manager counterparts at `modules/browsers/<name>/home.nix`. The pair `modules/meta/nixos-browser-helpers.nix` (exposed via `config.flake.lib.nixosBrowsers`) and `modules/hosts/common/browsers-base.nix` mirrors the app registry, importing every browser module into `flake.nixosModules.hosts-common`. Browser enablement still goes through `programs.<name>.extended.enable` in `apps-enable.nix`.

### Helper Functions

The module `modules/meta/nixos-app-helpers.nix` exposes helpers via `config.flake.lib.nixos`:

| Helper       | Signature                     | Purpose                            |
| ------------ | ----------------------------- | ---------------------------------- |
| `hasApp`     | `string -> bool`              | Check if app exists                |
| `getApp`     | `string -> module`            | Get single app (throws if missing) |
| `getApps`    | `[string] -> [module]`        | Get multiple apps                  |
| `getAllApps` | `[module]`                    | Get every discovered app module    |
| `getAppOr`   | `string -> default -> module` | Get app with fallback              |

### Usage Example

```nix
# modules/hosts/common/apps-base.nix
{ config, ... }:
let
  helpers = config._module.args.nixosAppHelpers;
in
{
  flake.nixosModules.hosts-common.imports = helpers.getAllApps;
}
```

### Guarded Lookups

For optional dependencies, use `hasApp` or `getAppOr`:

```nix
{ config, lib, ... }:
let
  nixos = config.flake.lib.nixos;
in
{
  configurations.nixos.system76.module.imports =
    lib.optionals (nixos.hasApp "steam") [
      (nixos.getApp "steam")
    ];
}
```

## `flake.lib` Namespaces

`flake.lib` exposes pure helper data and small utilities. All sub-namespaces are declared in `modules/meta/flake-output.nix` and populated by individual modules.

| Namespace                 | Type                               | Purpose                                                                                         |
| ------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------- |
| `flake.lib.meta`          | `anything`                         | Repo metadata (owner identity, hostnames, surface for `metaOwner` arg).                         |
| `flake.lib.nixos`         | `lazyAttrsOf anything`             | App-registry helpers (`hasApp`, `getApp`, ...) and host-conditional flags under `hosts.<name>`. |
| `flake.lib.nixosBrowsers` | `lazyAttrsOf anything`             | Browser-registry helpers (`hasBrowser`, `getBrowser`, ...) for `modules/browsers/`.             |
| `flake.lib.homeManager`   | `attrsOf anything` (via submodule) | Helpers and metadata used by Home Manager modules.                                              |
| `flake.lib.security`      | `attrsOf anything`                 | Shared SOPS helpers (e.g. `sopsInstallSecretsService`).                                         |
| `flake.lib.nixvim`        | `attrsOf anything`                 | Helpers for NixVim integrations and shared module shape.                                        |
| `flake.lib.xdg`           | `attrsOf anything`                 | Desktop file mappings, MIME helpers (consumed by `modules/meta/ci.nix`).                        |
| `flake.lib.agents`        | `attrsOf anything` (via submodule) | Registry and compiled outputs for MCP servers and skills (`modules/agents/*.nix`).              |
| `flake.lib.checks`        | `attrsOf anything`                 | Lightweight evaluation-only checks (no derivation builds).                                      |

Helpers should stay pure and idempotent; anything that needs heavy evaluation belongs in a module rather than a `flake.lib.*` entry.

## `perSystem` vs host overlays

This repository uses both patterns, for different purposes:

- `perSystem.packages` is used for flake-exposed tooling packages (for example, `generation-manager` and hook helpers in `modules/devshell.nix`).
- App packages in `packages/<name>/default.nix` are injected through per-app overlay modules under `modules/custom-overlays/<name>.nix`. Each registers `flake.customOverlays.<name>` and adds an overlay to `nixpkgs.overlays` that returns `<name> = final.callPackage ../../packages/<name> { }`, making the package available as `pkgs.<name>` when gated on the matching `programs.<name>.extended.enable`. `modules/hosts/common/custom-overlays-base.nix` imports every registered overlay into the shared `flake.nixosModules.hosts-common` aggregate, so an overlay only takes effect on hosts where its app is enabled.

This means these packages are **not** exposed under `.#packages.<system>.<name>`; they materialize as `pkgs.<name>` only inside a `nixosConfigurations.<host>` evaluation where the matching app is enabled.

## Shared System Helpers

| Module                                         | Export                                         | Scope           | Purpose                                           |
| ---------------------------------------------- | ---------------------------------------------- | --------------- | ------------------------------------------------- |
| `modules/system76/support.nix`                 | `flake.nixosModules."system76-support"`        | system76 only   | System76 kernel modules, firmware                 |
| `modules/hardware/monitors/lenovo-y27q-20.nix` | `flake.nixosModules."hardware-lenovo-y27q-20"` | shared (opt-in) | Monitor profile                                   |
| `modules/hosts/common/virtualization.nix`      | host options under `host.virtualization.*`     | shared          | Virtualization app toggles                        |
| `modules/tpnix/policy.nix`                     | `flake.lib.nixos.hosts.tpnix.*` flags          | tpnix only      | Host-conditional gating (e.g. `sopsRuntimeReady`) |

## The `flake.csec` Namespace

Cybersecurity-tooling NixOS modules register under `flake.csec.<feature>`, declared in `modules/meta/flake-output.nix` as `attrsOf deferredModule`. Each feature is a first-class entry rather than collapsing into a parent module like sub-keys under `flake.nixosModules.*` would (`lazyAttrsOf raw` does not give per-feature merge semantics without flat name mangling).

```nix
flake.csec = {
  wordlists = { ... };  # Kali-style symlinks under /usr/share/wordlists/
  # Future feature modules register here.
};
```

Hosts opt in explicitly by importing the module and toggling its enable flag:

```nix
# modules/system76/imports.nix
configurations.nixos.system76.module = {
  imports = [
    config.flake.csec.wordlists
    # ...
  ];
  csec.wordlists.enable = true;
};
```

| Module                       | Export                 | Purpose                                                                                               |
| ---------------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------- |
| `modules/csec/wordlists.nix` | `flake.csec.wordlists` | Kali-style wordlist symlinks populated at activation from `pkgs.wordlists` and app-owned manual links |

## System-Level Utilities

| Module                                    | Purpose                                        |
| ----------------------------------------- | ---------------------------------------------- |
| `modules/meta/ci.nix`                     | Validates app helper namespace                 |
| `modules/files.nix`                       | Regenerates managed files (README, .sops.yaml) |
| `modules/meta/nixpkgs-allowed-unfree.nix` | Unfree package allowlist                       |

## Next Steps

- [Home Manager](04-home-manager.md) -- user-level aggregators
- [Host Composition](05-host-composition.md) -- assembling hosts from modules
- [Apps Module Style Guide](../guides/apps-module-style-guide.md) -- per-app conventions
