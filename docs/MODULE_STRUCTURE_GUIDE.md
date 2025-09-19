# Module Structure Guide

This document shows how modules are authored and consumed in this flake-parts + import-tree repository. Read it together with `docs/DENDRITIC_PATTERN_REFERENCE.md` for the overall pattern.

## Key Concepts

- Every `.nix` file under `modules/` (unless prefixed with `_`) is a flake-parts module automatically imported by `import-tree`.
- Modules register themselves under the aggregators exposed by this flake:
  - `flake.nixosModules.<name>` for system configuration.
  - `flake.homeManagerModules.<name>` and `flake.homeManagerModules.apps.<name>` for Home Manager.
  - `configurations.nixos.<host>.module` for complete host definitions (transformed into `nixosConfigurations.<host>`).
- Consumers compose these exports by *name*, never by literal path.

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
{ config, ... }:
{
  configurations.nixos.system76.module = {
    imports = with config.flake.nixosModules; [
      base
      pc
      workstation
      "role-dev"
    ];
  };
}
```

The helper in `modules/configurations/nixos.nix` transforms these into `nixosConfigurations.system76` outputs.

## Home Manager Aggregator

Home Manager modules follow the same rules:

- Shared modules land in `flake.homeManagerModules.base` and `flake.homeManagerModules.gui`.
- App-specific modules live under `flake.homeManagerModules.apps.<name>`.
- Roles are pure data in `flake.lib.homeManager.roles` and resolved in `modules/home-manager/nixos.nix`. See `docs/home-manager-aggregator.md` for details.

## Common Pitfalls (and Fixes)

| Mistake | Fix |
|---------|-----|
| `{ config, lib, pkgs, ... }:` at the top of the file | Remove `pkgs` from the outer scope and wrap the exported value in a function that receives `{ pkgs, ... }`. |
| Referencing modules via `./path/to/module.nix` | Import via `config.flake.nixosModules.<name>` or `config.flake.homeManagerModules.<name>` instead. |
| Using `with config.flake.nixosModules.apps;` in roles | Replace with `lib.hasAttrByPath` + `lib.getAttrFromPath` (already enforced by pre-commit hooks). |
| Forgetting to guard optional modules | Wrap definitions with `lib.mkIf` or `lib.optionals` so evaluation succeeds even when hardware/services are absent. |

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
