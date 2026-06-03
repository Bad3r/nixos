# Pattern Overview

The Dendritic Pattern treats every file under `modules/` as a flake-parts module, composing them organically through shared aggregators. This repository follows the canonical implementation from [mightyiam/infra](https://github.com/mightyiam/infra).

## Core Principle

Add a module, export it under a namespace, and the flake wires it up automatically. No manual import lists to maintain.

## Automatic Module Discovery

The `import-tree` function (see `flake.nix`) recursively imports every `.nix` file under `modules/` that does **not** start with an underscore.

```
modules/
├── apps/
│   ├── firefox.nix      ← Imported automatically
│   └── _experimental.nix ← Ignored (underscore prefix)
├── system76/
│   └── boot.nix         ← Imported automatically (system76 host)
├── tpnix/
│   └── boot.nix         ← Imported automatically (tpnix host)
└── _scratch/            ← Entire directory ignored
```

**Key rules:**

- Prefix experimental or parked files with `_` to exclude them without deleting history
- Put unfinished work under `_scratch/` or `_archive/` directories
- Prefer aggregator references (`config.flake.nixosModules.*`, `config.flake.homeManagerModules.*`) in host/app composition instead of literal path imports
- `_`-prefixed files can still be imported explicitly from a non-underscored module when you intentionally want private building blocks (for example, `modules/languages/lang.nix` importing `./_lang-*.nix`)

## How Files Become Modules

Each `.nix` file is a flake-parts module that registers itself under one or more aggregator namespaces:

```nix
# modules/apps/jq.nix
_:
let
  JqModule =
    { config, lib, pkgs, ... }:
    let
      cfg = config.programs.jq.extended;
    in
    {
      options.programs.jq.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jq.";
        };
        package = lib.mkPackageOption pkgs "jq" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.jq = JqModule;
}
```

The file:

1. Is discovered by `import-tree`
2. Evaluated as a flake-parts module
3. Contributes to `flake.nixosModules.apps.jq`
4. Can be consumed by hosts via `config.flake.nixosModules.apps.jq`

Per-app modules follow this `programs.<name>.extended.enable` shape (the header doc-comment is elided above). Hosts do not import each app by hand: the apps-enable baseline flips the toggles. See [NixOS Modules](03-nixos-modules.md) and [Host Composition](05-host-composition.md).

## Aggregator Namespaces

This flake exposes the following top-level aggregators (all declared in `modules/meta/flake-output.nix`):

| Namespace                  | Purpose                             | Typical Exports                                                                                        |
| -------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `flake.nixosModules`       | System-level configuration          | `base`, hardware profiles, `apps.<name>`                                                               |
| `flake.homeManagerModules` | Home Manager configuration          | `base`, `gui`, `apps.<name>`                                                                           |
| `flake.csec`               | Cybersecurity feature modules       | `wordlists` (per-feature, opt-in via host import + enable)                                             |
| `flake.customOverlays`     | Per-app `nixpkgs` overlay modules   | `<name>` (auto-discovered from `modules/custom-overlays/`, gated on `programs.<name>.extended.enable`) |
| `flake.lib.*`              | Helper functions and small metadata | `meta`, `nixos`, `homeManager`, `security`, `nixvim`, `xdg`, `agents`, `checks`                        |

`flake.nixosModules` and `flake.homeManagerModules` collect modules that hosts compose by name. `flake.csec` and `flake.customOverlays` are each a separate `attrsOf deferredModule` so every feature or overlay is a first-class entry that hosts opt into individually (see [NixOS Modules](03-nixos-modules.md#persystem-vs-host-overlays) for how overlays are wired). `flake.lib` holds pure helper data (see [NixOS Modules](03-nixos-modules.md#flakelib-namespaces) for the full breakdown).

Modules register themselves under these namespaces. Consumers compose features by name rather than by file path.

## Why "Dendritic"?

The pattern resembles dendritic (tree-like) growth:

- Files can be added anywhere under `modules/`
- No central registry to update
- Structure grows organically as needs evolve
- Refactoring (moving files) doesn't break imports

## Next Steps

- [Module Authoring](02-module-authoring.md) -- how to write modules correctly
- [NixOS Modules](03-nixos-modules.md) -- system-level aggregator details
- [Home Manager](04-home-manager.md) -- user-level aggregator details
