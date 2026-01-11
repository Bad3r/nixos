# Module Authoring

This document covers how to write modules correctly in this flake-parts + import-tree repository.

## File Placement

| Location                     | Purpose               | Export Pattern                         |
| ---------------------------- | --------------------- | -------------------------------------- |
| `modules/apps/<name>.nix`    | Per-app modules       | `flake.nixosModules.apps.<name>`       |
| `modules/hm-apps/<name>.nix` | Per-app HM modules    | `flake.homeManagerModules.apps.<name>` |
| `modules/<domain>/`          | Higher-level features | `flake.nixosModules.<feature>`         |
| `modules/system76/`          | Host-specific config  | `configurations.nixos.system76.module` |

**Rule:** If a module only installs packages, put it in `modules/apps/`. If it configures services or composes multiple apps, use a domain directory.

## Authoring Patterns

### Pattern 1: Module That Needs `pkgs`

```nix
# modules/development/json-tools.nix
{ config, ... }:
{
  flake.homeManagerModules.base = { pkgs, ... }: {
    home.packages = with pkgs; [ jq yq jnv ];
  };
}
```

The outer function does **not** receive `pkgs` — flake-parts doesn't provide it at that level. The exported value must be a function that receives `{ pkgs, ... }`.

### Pattern 2: Module Without `pkgs`

```nix
# modules/networking/ssh-hosts.nix
{ lib, ... }:
{
  flake.homeManagerModules.base = _: {
    programs.ssh.knownHosts = lib.mkMerge [ /* ... */ ];
  };
}
```

Return an attribute set directly when you don't need extra arguments.

### Pattern 3: Multi-Namespace Module

```nix
# modules/git/git.nix
{ ... }:
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

### Pattern 4: Extending Existing Namespaces

```nix
# modules/base/nix-settings.nix
{ lib, ... }:
{
  flake.nixosModules.base = lib.mkIf true {
    nix.settings.experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
  };
}
```

Use `lib.mkIf`, `lib.mkMerge`, and other option helpers to extend shared modules without clobbering defaults.

### Pattern 5: Host Module

```nix
# modules/system76/imports.nix
{ config, lib, ... }:
{
  configurations.nixos.system76.module = {
    imports = lib.filter (module: module != null) [
      (config.flake.nixosModules.base or null)
      (config.flake.nixosModules."system76-support" or null)
    ];
  };
}
```

See [Host Composition](05-host-composition.md) for details.

## Common Pitfalls

| Mistake                                   | Fix                                                                     |
| ----------------------------------------- | ----------------------------------------------------------------------- |
| `{ config, lib, pkgs, ... }:` at file top | Remove `pkgs` from outer scope; wrap exported value in `{ pkgs, ... }:` |
| `imports = [ ./path/to/module.nix ]`      | Use `config.flake.nixosModules.<name>` instead                          |
| `with config.flake.nixosModules.apps;`    | Use `config.flake.lib.nixos.getApps` for cached lookups                 |
| Forgetting to guard optional modules      | Wrap with `lib.mkIf` or `lib.optionals`                                 |

## The Two-Context Problem

Modules that export `flake.homeManagerModules.*` or `flake.nixosModules.*` are evaluated in **two distinct contexts**:

| Context                       | `config` refers to | Access available                     |
| ----------------------------- | ------------------ | ------------------------------------ |
| **Flake-parts** (outer scope) | Flake-level config | `config.flake.*`                     |
| **Module** (inner definition) | NixOS/HM config    | `config.home.*`, `config.services.*` |

Accessing `config.flake.*` inside the exported module definition **will fail** because that context doesn't have flake-level config.

### Anti-Patterns

```nix
# WRONG: Eager evaluation in top-level let binding
let
  path = "${config.home.homeDirectory}/.config/app";  # config.home doesn't exist here!
in
{ config = { ... }; }

# WRONG: Accessing config.flake in inner context
{ config, lib, ... }:
{
  flake.homeManagerModules.base = args: {
    home.packages = [ config.flake.lib.customPackage ];  # config.flake doesn't exist here!
  };
}
```

### Safe Patterns

```nix
# CORRECT: Access config.flake in outer (flake-parts) context
{ config, lib, ... }:
let
  owner = config.flake.lib.meta.owner;  # Accessed in flake-parts context
in
{
  flake.homeManagerModules.base = args: {
    home.username = owner.username;  # Use value from outer scope
  };
}

# CORRECT: Lazy evaluation inside config block
{
  config = {
    some.option = "${config.home.homeDirectory}/.config/app";  # Evaluated after merge
  };
}

# CORRECT: Using lib.mkMerge for conditional evaluation
{
  config = lib.mkMerge [
    {
      # Always evaluated
    }
    (lib.mkIf condition {
      path = "${config.something}";  # Config access safe here
    })
  ];
}
```

### Rule of Thumb

| Location                 | Safe to Access                                              |
| ------------------------ | ----------------------------------------------------------- |
| Top-level `let` bindings | Constants, inputs, `config.flake.*`                         |
| Inner module `config`    | NixOS/HM options (`config.home.*`, `config.services.*`)     |
| String interpolations    | Defer to option definitions or use `lib.mkMerge`/`lib.mkIf` |

## Introspection & Debugging

```bash
# Enter repl with flake context
nix develop -c nix repl
> :lf .
> :p config.flake.nixosModules            # Inspect registered modules
> :p config.flake.homeManagerModules.apps # Inspect Home Manager apps

# Evaluate specific host option
nix eval .#nixosConfigurations.system76.config.boot.loader
```

## Next Steps

- [NixOS Modules](03-nixos-modules.md) — system aggregator details
- [Home Manager](04-home-manager.md) — HM aggregator details
- [Reference](06-reference.md) — validation commands
