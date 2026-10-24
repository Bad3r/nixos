# NixOS Modules

System modules register under the `flake.nixosModules` aggregator, and their helpers sit in `flake.lib`.
The `flake.lib` and `flake.csec` namespaces are in [flake.lib and flake.csec Namespaces](03-nixos-modules-namespaces.md).

## The `flake.nixosModules` Namespace

All system modules feed into `flake.nixosModules`, so hosts compose features by name rather than by path.

```nix
# Structure
flake.nixosModules = {
  base = { ... };                    # Core system settings
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

Per-app modules live under `flake.nixosModules.apps.<name>` and follow the [Apps Module Style Guide](../guides/apps-module-style-guide.md).
Rows in the [App registry](../guides/apps-module-registry.md) switch them on per host.

Browsers live under `flake.nixosModules.browsers.<name>` instead, from `modules/browsers/<name>/apps.nix`, with Home Manager counterparts in `modules/browsers/<name>/home.nix`.
`modules/meta/nixos-browser-helpers.nix`, exposed as `config.flake.lib.nixosBrowsers`, and `modules/hosts/common/browsers-base.nix` mirror the app registry, importing every browser module into `flake.nixosModules.hosts-common`.
A browser's row is a `programs.<name>.extended.enable` row like any other app's.

### Helper Functions

`modules/meta/nixos-app-helpers.nix` exposes these helpers through `config.flake.lib.nixos`:

| Helper       | Signature                     | Purpose                            |
| ------------ | ----------------------------- | ---------------------------------- |
| `hasApp`     | `string -> bool`              | Check if app exists                |
| `getApp`     | `string -> module`            | Get single app (throws if missing) |
| `getApps`    | `[string] -> [module]`        | Get multiple apps                  |
| `getAllApps` | `[module]`                    | Get every discovered app module    |
| `getAppOr`   | `string -> default -> module` | Get app with fallback              |

### Usage Example

```nix
# modules/hosts/common/apps-base.nix (simplified)
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
  configurations.nixos.songbird.module.imports =
    lib.optionals (nixos.hasApp "steam") [
      (nixos.getApp "steam")
    ];
}
```

## `perSystem` vs host overlays

- `perSystem.packages` holds flake-exposed tooling packages, for example `generation-manager` from `modules/apps/generation-manager.nix` and the hook helpers in `modules/meta/devshell.nix`.
- App packages under `packages/<name>/default.nix` reach `pkgs` through overlay modules gated on their app's row; [Custom package overlays](../guides/custom-packages-overlays.md) covers the wiring.
  An app folder's `package.nix`, such as `modules/apps/restringer/package.nix`, also exposes the package as `.#packages.<system>.<name>`.

## Shared System Helpers

| Module                            | Export                                | Scope    | Purpose                 |
| --------------------------------- | ------------------------------------- | -------- | ----------------------- |
| `modules/hosts/<host>/policy.nix` | `flake.lib.nixos.hosts.<host>.*` data | per host | Gates and common values |

A host's `policy.nix` carries its readiness gates and the values common modules read.

## System-Level Utilities

| Module                                    | Purpose                        |
| ----------------------------------------- | ------------------------------ |
| `modules/meta/ci.nix`                     | Validates app helper namespace |
| `modules/meta/nixpkgs-allowed-unfree.nix` | Builds the unfree predicate    |

## Unfree Packages

An unfree package is declared with `nixpkgs.allowedUnfreePackages` next to the module that installs it.
`modules/meta/nixpkgs-allowed-unfree.nix` declares that option at flake-parts scope and only builds the predicate from it; no NixOS-scope allowlist exists.

## Next Steps

- [Home Manager](04-home-manager.md) -- user-level aggregators
- [Host Composition](05-host-composition.md) -- assembling hosts from modules
- [Apps Module Style Guide](../guides/apps-module-style-guide.md) -- per-app conventions
