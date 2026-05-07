# Module Authoring

This document covers how to write modules correctly in this flake-parts + import-tree repository.

## File Placement

| Location                     | Purpose               | Export Pattern                                                                    |
| ---------------------------- | --------------------- | --------------------------------------------------------------------------------- |
| `modules/apps/<name>.nix`    | Per-app modules       | `flake.nixosModules.apps.<name>`                                                  |
| `modules/hm-apps/<name>.nix` | Per-app HM modules    | `flake.homeManagerModules.apps.<name>`                                            |
| `modules/<domain>/`          | Higher-level features | `flake.nixosModules.<feature>`                                                    |
| `modules/<host>/`            | Host-specific config  | `configurations.nixos.<host>.module` (e.g. `modules/system76/`, `modules/tpnix/`) |

**Rule:** If a module only installs packages, put it in `modules/apps/`. If it configures services or composes multiple apps, use a domain directory.

## Authoring Patterns

### Pattern 1: Module That Needs `pkgs`

```nix
# modules/development/json-tools.nix
{ config, ... }:
{
  flake.homeManagerModules.base = { pkgs, ... }: {
    home.packages = with pkgs; [ jq jnv ];
  };
}
```

The outer function does **not** receive `pkgs` -- flake-parts doesn't provide it at that level. The exported value must be a function that receives `{ pkgs, ... }`.

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
# modules/stylix/stylix.nix
{ inputs, ... }:
{
  flake.nixosModules.base = {
    imports = [ inputs.stylix.nixosModules.stylix ];
  };

  flake.homeManagerModules.base = {
    imports = [ inputs.stylix.homeModules.stylix ];
  };

  flake.homeManagerModules.apps.stylix-gui = { ... }: {
    # GUI-only HM theming
  };
}
```

One file can populate both aggregators. Keep the scopes independent.

### Pattern 4: Extending Existing Namespaces

```nix
# modules/base/nix-settings.nix
{ config, ... }:
{
  config = {
    nix.settings.experimental-features = [ "nix-command" "flakes" "pipe-operators" "recursive-nix" ];

    flake.nixosModules.base.nix = {
      inherit (config.nix) settings;
    };

    flake.homeManagerModules.base = _: {
      nix.settings = config.nix.settings;
    };
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
    imports =
      [ config.flake.nixosModules.base ]
      ++ lib.optionals (lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config) [
        config.flake.nixosModules."system76-support"
      ];
  };
}
```

See [Host Composition](05-host-composition.md) for details.

## Custom Module Arguments

Hosts inject a small set of custom arguments via `_module.args` so that downstream modules can receive them as ordinary function parameters. Each host's `modules/<host>/imports.nix` sets them in two places: on the deferred `configurations.nixos.<host>.module` and on the wrapping `nixosSystem` call (so they are available to both flake-parts and the host evaluation).

| Arg               | Type  | Source                               | Use                                                                           |
| ----------------- | ----- | ------------------------------------ | ----------------------------------------------------------------------------- |
| `metaOwner`       | attrs | `modules/meta/owner.nix`             | Owner identity (`username`, `sshKeys`); used by HM users, secret modules.     |
| `secretsRoot`     | path  | Repo `secrets/` directory            | Base for `sopsFile` references; lets secrets modules guard with `pathExists`. |
| `inputs`          | attrs | flake-parts `specialArgs`            | Flake inputs propagated into NixOS modules without re-importing the flake.    |
| `nixosAppHelpers` | attrs | `modules/meta/nixos-app-helpers.nix` | Same helpers exposed at `config.flake.lib.nixos`; convenient inside hosts.    |

```nix
# modules/home/context7-secrets.nix
{ lib, metaOwner, secretsRoot, ... }:
let
  ctxFile = "${secretsRoot}/context7.yaml";
in
{
  config = lib.mkIf (builtins.pathExists ctxFile) {
    sops.secrets."context7/api-key" = {
      sopsFile = ctxFile;
      owner = metaOwner.username;
      # ...
    };
  };
}
```

Treat custom args as the contract between hosts and downstream modules. Adding a new arg requires updating every `_module.args` block that sets it; missing args surface as evaluation-time errors that name the missing parameter.

## Common Pitfalls

| Mistake                                   | Fix                                                                     |
| ----------------------------------------- | ----------------------------------------------------------------------- |
| `{ config, lib, pkgs, ... }:` at file top | Remove `pkgs` from outer scope; wrap exported value in `{ pkgs, ... }:` |
| `imports = [ ./path/to/module.nix ]`      | Use `config.flake.nixosModules.<name>` instead                          |
| `with config.flake.nixosModules.apps;`    | Use `config.flake.lib.nixos.getApps` / `getAllApps` helpers             |
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
# List module namespaces
nix eval --accept-flake-config --json .#nixosModules --apply builtins.attrNames
nix eval --accept-flake-config --json .#homeManagerModules.apps --apply builtins.attrNames

# Evaluate a specific host option (substitute the host name)
nix eval .#nixosConfigurations.<host>.config.boot.loader

# List the hosts available in the current checkout
nix eval --accept-flake-config --json .#nixosConfigurations --apply builtins.attrNames
```

## Next Steps

- [NixOS Modules](03-nixos-modules.md) -- system aggregator details
- [Home Manager](04-home-manager.md) -- HM aggregator details
- [Reference](06-reference.md) -- validation commands
