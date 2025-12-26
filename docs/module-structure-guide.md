# Module Structure Guide

This document shows how modules are authored and consumed in this flake-parts + import-tree repository. Start with `docs/configuration-architecture.md` for the end-to-end architecture map, then return here for module-level authoring patterns. `docs/dendritic-pattern-reference.md` focuses on the auto-import foundations that make these patterns possible.

## Key Concepts

- Every `.nix` file under `modules/` (unless prefixed with `_`) is a flake-parts module automatically imported by `import-tree`.
- Modules register themselves under the aggregators exposed by this flake:
  - `flake.nixosModules.<name>` for system configuration.
  - `flake.homeManagerModules.<name>` and `flake.homeManagerModules.apps.<name>` for Home Manager.
  - `configurations.nixos.<host>.module` for complete host definitions (transformed into `nixosConfigurations.<host>`).
- Consumers compose these exports by _name_, never by literal path.

## File Placement Rules

- Store per-app modules in `modules/apps/<name>.nix`. Each file should export `flake.nixosModules.apps.<name>` and, when needed, mirror the package into default bundles such as `flake.nixosModules.workstation`.
- Reserve domain directories under `modules/<domain>/` for higher-level features that configure services or compose multiple apps. If a module only installs packages, move it into `modules/apps/` and have host modules import it.

## Authoring Patterns

### 1. Module That Needs `pkgs`

```nix
# modules/development/json-tools.nix
{ config, ... }:
{
  flake.homeManagerModules.base = { pkgs, ... }: {
    home.packages = with pkgs; [ jq yq jnv ];
  };
}
```

- The outer function **does not** receive `pkgs`—flake-parts does not provide it at that level.
- The value assigned to the aggregator key is a function (`{ pkgs, ... }:`) so you can access packages.

### 2. Module Without `pkgs`

```nix
# modules/networking/ssh-hosts.nix
{ lib, ... }:
{
  flake.homeManagerModules.base = _: {
    programs.ssh.knownHosts = lib.mkMerge [ … ];
  };
}
```

Return an attribute set directly when you do not need extra arguments.

### 3. Multi-namespace Module

```nix
# modules/git/git.nix
{ pkgs, ... }:
{
  flake.nixosModules.git = { ... }: {
    programs.git.enable = true;
  };

  flake.homeManagerModules.base = { pkgs, ... }: {
    programs.git = {
      enable = true;
      package = pkgs.gitFull;
    };
  };
}
```

One file can populate both aggregators. Keep the scopes independent.

### 4. Extending Existing Namespaces

```nix
# modules/base/nix-settings.nix
{ lib, ... }:
{
  flake.nixosModules.base = lib.mkIf true {
    nix.settings.experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
  };
}
```

Use `lib.mkIf`, `lib.mkMerge`, and other option helpers to extend shared modules without clobbering their defaults.

### 5. Host Modules

Host definitions bundle modules together and live under `configurations.nixos.<host>.module`.

```nix
# modules/system76/imports.nix
{ config, lib, ... }:
{
  configurations.nixos.system76.module = {
    imports = lib.filter (module: module != null) [
      (config.flake.nixosModules.base or null)
      (config.flake.nixosModules."system76-support" or null)
      (config.flake.nixosModules."hardware-lenovo-y27q-20" or null)
    ];
  };
}
```

The helper in `modules/configurations/nixos.nix` transforms these into `nixosConfigurations.system76` outputs.

## Home Manager Aggregator

Home Manager modules follow the same rules:

- Shared modules land in `flake.homeManagerModules.base` and `flake.homeManagerModules.gui`.
- App-specific modules live under `flake.homeManagerModules.apps.<name>`.
- Baseline app imports are listed directly in `modules/home-manager/nixos.nix`, which resolves app modules via guarded lookups. See `docs/home-manager-aggregator.md` for details.

## Common Pitfalls (and Fixes)

| Mistake                                              | Fix                                                                                                                |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `{ config, lib, pkgs, ... }:` at the top of the file | Remove `pkgs` from the outer scope and wrap the exported value in a function that receives `{ pkgs, ... }`.        |
| Referencing modules via `./path/to/module.nix`       | Import via `config.flake.nixosModules.<name>` or `config.flake.homeManagerModules.<name>` instead.                 |
| Using `with config.flake.nixosModules.apps;`         | Replace with `config.flake.lib.nixos.getApps` / `getApp` so lookups stay pure and cached.                          |
| Forgetting to guard optional modules                 | Wrap definitions with `lib.mkIf` or `lib.optionals` so evaluation succeeds even when hardware/services are absent. |

## Config Access Patterns and Evaluation Order

### The Two-Context Problem

Modules that export `flake.homeManagerModules.*` or `flake.nixosModules.*` are evaluated in **two distinct contexts**:

1. **Flake-parts context** - where `config.flake.*` exists (outer module scope)
2. **Module context** - where `config` refers to the NixOS/Home Manager configuration (inner module definition)

Accessing `config.flake.*` inside the exported module definition will fail because that context doesn't have access to flake-level config.

### Anti-Patterns (Will Cause "cannot coerce null to a string")

```nix
# ❌ WRONG: Eager evaluation in top-level let binding
let
  path = "${config.home.homeDirectory}/.config/app";
in
{ config = { ... }; }

# ❌ WRONG: Accessing config.flake in inner context
{ config, lib, ... }:
{
  flake.homeManagerModules.base = args: {
    home.packages = [ config.flake.lib.customPackage ];  # config.flake doesn't exist here!
  };
}
```

### Safe Patterns

```nix
# ✅ CORRECT: Access config.flake in outer (flake-parts) context
{ config, lib, ... }:
let
  owner = config.flake.lib.meta.owner;  # ← Access in flake-parts context
in
{
  flake.homeManagerModules.base = args: {
    # Use 'owner' from outer scope, not config access
    home.username = owner.username;
  };
}

# ✅ CORRECT: Lazy evaluation inside config block
{
  config = {
    some.option = "${config.home.homeDirectory}/.config/app";  # Evaluated after merge
  };
}

# ✅ CORRECT: Using lib.mkMerge for conditional evaluation
{
  config = lib.mkMerge [
    {
      # Always evaluated
    }
    (lib.mkIf condition {
      # Conditionally evaluated - config access safe here
      path = "${config.something}";
    })
  ];
}
```

### Rule of Thumb

- **Top-level let bindings**: Only constants, inputs, and `config.flake.*` access
- **Inner module config**: All other `config.*` access (NixOS/HM options)
- **String interpolations**: Defer to option definitions or use `lib.mkMerge`/`lib.mkIf`

For historical context on the home-manager evaluation order changes that necessitated these patterns, see git history around commit d1fc28275 (Dec 2025).

## Introspection & Debugging

```bash
nix develop -c nix repl
> :lf .
> :p config.flake.nixosModules            # inspect registered modules
> :p config.flake.homeManagerModules.apps # inspect Home Manager apps

nix eval .#nixosConfigurations.system76.config.boot.loader
```

`generation-manager score` evaluates a set of structural checks (no literal imports, required metadata, etc.) and must stay at **≥ 90/90** before merging.

## Migration Tips

1. Split large legacy configurations into logical modules under `modules/<domain>/`.
2. Export each feature under a descriptive key (e.g. `flake.nixosModules.pipewire`).
3. Move host-specific knobs into `configurations.nixos.<host>.module`.
4. Replace `imports = [ ./foo.nix ];` with aggregator references.
5. Run the validation suite: `nix fmt`, `nix develop -c pre-commit run --all-files`, `generation-manager score`, `nix flake check --accept-flake-config`.

Following these patterns keeps modules composable and predictable throughout the Dendritic Pattern.
