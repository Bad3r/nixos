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
    firefox = { ... };
    steam = { ... };
    # ...
  };
};
```

## App Registry

Per-app modules live under `flake.nixosModules.apps.<name>` and follow the pattern in [Apps Module Style Guide](../guides/apps-module-style-guide.md).

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
# modules/system76/apps-base.nix
{ config, ... }:
let
  helpers = config._module.args.nixosAppHelpers;
in
{
  configurations.nixos.system76.module.imports =
    helpers.getAllApps;
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

## `perSystem` vs host overlays

This repository uses both patterns, for different purposes:

- `perSystem.packages` is used for flake-exposed tooling packages (for example, `generation-manager` and hook helpers).
- Host app packages in `packages/<name>/default.nix` are injected through the System76 overlay in `modules/system76/custom-packages-overlay.nix`, then consumed as regular `pkgs.<name>` values by app modules.

This means many host-only packages are **not** available under `.#packages.<system>.<name>` directly; they are available inside the host evaluation (`nixosConfigurations.system76`) where the overlay is active.

## Shared System Helpers

| Module                                         | Export                                         | Purpose                           |
| ---------------------------------------------- | ---------------------------------------------- | --------------------------------- |
| `modules/system76/support.nix`                 | `flake.nixosModules."system76-support"`        | System76 kernel modules, firmware |
| `modules/hardware/monitors/lenovo-y27q-20.nix` | `flake.nixosModules."hardware-lenovo-y27q-20"` | Monitor profile                   |
| `modules/system76/virtualization.nix`          | host options under `system76.virtualization.*` | Virtualization app toggles        |

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
