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

| Helper     | Signature                     | Purpose                            |
| ---------- | ----------------------------- | ---------------------------------- |
| `hasApp`   | `string -> bool`              | Check if app exists                |
| `getApp`   | `string -> module`            | Get single app (throws if missing) |
| `getApps`  | `[string] -> [module]`        | Get multiple apps                  |
| `getAppOr` | `string -> default -> module` | Get app with fallback              |

### Usage Example

```nix
# modules/system76/apps-enable.nix
{ config, ... }:
{
  configurations.nixos.system76.module.imports =
    config.flake.lib.nixos.getApps [
      "python"
      "uv"
      "ruff"
      "pyright"
    ];
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

## perSystem and Custom Packages

Custom packages under `packages/<name>/default.nix` are exposed via the flake-parts `perSystem` mechanism:

```nix
# Accessing packages
perSystem.packages.raindrop
perSystem.packages.dnsleak

# From command line
nix build .#raindrop
nix build .#packages.x86_64-linux.raindrop
```

App modules can wire these into system packages:

```nix
# modules/apps/raindrop.nix
{ config, ... }:
{
  flake.nixosModules.apps.raindrop = { pkgs, ... }: {
    environment.systemPackages = [
      config.flake.packages.${pkgs.system}.raindrop
    ];
  };
}
```

See [Custom Packages Style Guide](../guides/custom-packages-style-guide.md) for package authoring conventions.

## Shared System Helpers

| Module                                  | Export                                         | Purpose                           |
| --------------------------------------- | ---------------------------------------------- | --------------------------------- |
| `modules/hardware/system76-support.nix` | `flake.nixosModules."system76-support"`        | System76 kernel modules, firmware |
| `modules/hardware/lenovo-y27q-20.nix`   | `flake.nixosModules."hardware-lenovo-y27q-20"` | Monitor profile                   |
| `modules/virtualization/*.nix`          | `flake.nixosModules.{virt,docker,libvirt,...}` | Virtualization stacks             |

## System-Level Utilities

| Module                                    | Purpose                                        |
| ----------------------------------------- | ---------------------------------------------- |
| `modules/meta/ci.nix`                     | Validates app helper namespace                 |
| `modules/files.nix`                       | Regenerates managed files (README, .sops.yaml) |
| `modules/meta/nixpkgs-allowed-unfree.nix` | Unfree package allowlist                       |

## Next Steps

- [Home Manager](04-home-manager.md) — user-level aggregators
- [Host Composition](05-host-composition.md) — assembling hosts from modules
- [Apps Module Style Guide](../guides/apps-module-style-guide.md) — per-app conventions
