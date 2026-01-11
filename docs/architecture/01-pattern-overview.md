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
│   └── boot.nix         ← Imported automatically
└── _scratch/            ← Entire directory ignored
```

**Key rules:**

- Prefix experimental or parked files with `_` to exclude them without deleting history
- Put unfinished work under `_scratch/` or `_archive/` directories
- Never use literal `./path/to/module.nix` imports — move files freely since consumers import by name

## How Files Become Modules

Each `.nix` file is a flake-parts module that registers itself under one or more aggregator namespaces:

```nix
# modules/apps/jq.nix
_: {
  flake.nixosModules.apps.jq = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.jq ];
  };
}
```

The file:

1. Is discovered by `import-tree`
2. Evaluated as a flake-parts module
3. Contributes to `flake.nixosModules.apps.jq`
4. Can be consumed by hosts via `config.flake.nixosModules.apps.jq`

## Aggregator Namespaces

This flake exposes two primary aggregators:

| Namespace                  | Purpose                    | Typical Exports                          |
| -------------------------- | -------------------------- | ---------------------------------------- |
| `flake.nixosModules`       | System-level configuration | `base`, hardware profiles, `apps.<name>` |
| `flake.homeManagerModules` | Home Manager configuration | `base`, `gui`, `apps.<name>`             |

Modules register themselves under these namespaces. Consumers compose features by name rather than by file path.

## Why "Dendritic"?

The pattern resembles dendritic (tree-like) growth:

- Files can be added anywhere under `modules/`
- No central registry to update
- Structure grows organically as needs evolve
- Refactoring (moving files) doesn't break imports

## Next Steps

- [Module Authoring](02-module-authoring.md) — how to write modules correctly
- [NixOS Modules](03-nixos-modules.md) — system-level aggregator details
- [Home Manager](04-home-manager.md) — user-level aggregator details
