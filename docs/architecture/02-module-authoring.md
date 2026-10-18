# Module Authoring

Every `.nix` file under `modules/` is a flake-parts module that import-tree loads; these rules place and write one.

- [Authoring Patterns](02-module-authoring-patterns.md): module shapes with and without `pkgs`, across namespaces, and for hosts.
- [Custom Module Arguments](02-module-authoring-arguments.md): the repo-specific arguments every host module receives.

## File Placement

| Location                           | Purpose                | Export Pattern                             |
| ---------------------------------- | ---------------------- | ------------------------------------------ |
| `modules/apps/<name>.nix`          | Single-file app        | `flake.nixosModules.apps.<name>`           |
| `modules/apps/<name>/nixos.nix`    | App folder: NixOS      | `flake.nixosModules.apps.<name>`           |
| `modules/apps/<name>/home.nix`     | App folder: HM         | `flake.homeManagerModules.apps.<name>`     |
| `modules/apps/<name>/overlay.nix`  | App folder: overlay    | `flake.customOverlays.<name>`              |
| `modules/apps/<name>/package.nix`  | App folder: flake pkgs | `perSystem.packages.*`                     |
| `modules/browsers/<name>/apps.nix` | Per-browser modules    | `flake.nixosModules.browsers.<name>`       |
| `modules/browsers/<name>/home.nix` | Per-browser HM modules | `flake.homeManagerModules.browsers.<name>` |
| `modules/<domain>/`                | Higher-level features  | `flake.nixosModules.<feature>`             |
| `modules/<host>/`                  | Host-specific config   | `configurations.nixos.<host>.module`       |

A module that only installs a package belongs in `modules/apps/`; one that configures services or composes several apps belongs in a domain directory.
An app gets a folder once it has more than one module file, as [File layout](../guides/apps-module-style-guide.md#file-layout) describes.
A domain, host, or hardware module that needs a program turns the program's row on instead of installing it, per [Package ownership](../guides/apps-module-registry.md#package-ownership).

## Common Pitfalls

- `{ config, lib, pkgs, ... }:` at the file top: remove `pkgs` from the outer scope and wrap the exported value in `{ pkgs, ... }:`.
- `imports = [ ./path/to/module.nix ]`: use `config.flake.nixosModules.<name>` instead.
- `with config.flake.nixosModules.apps;`: use the `config.flake.lib.nixos.getApps` or `getAllApps` helpers.
- An unguarded optional module: wrap it with `lib.mkIf` or `lib.optionals`.

## The Two-Context Problem

Modules that export `flake.homeManagerModules.*` or `flake.nixosModules.*` are evaluated in **two distinct contexts**:

| Context                       | `config` refers to | Access available                     |
| ----------------------------- | ------------------ | ------------------------------------ |
| **Flake-parts** (outer scope) | Flake-level config | `config.flake.*`                     |
| **Module** (inner definition) | NixOS/HM config    | `config.home.*`, `config.services.*` |

Accessing `config.flake.*` inside the exported module definition **fails**, because that context has no flake-level config.

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

- Top-level `let` bindings: constants, inputs, and `config.flake.*`.
- The inner module's `config`: NixOS and Home Manager options, such as `config.home.*` and `config.services.*`.
- String interpolations: defer them to option definitions, or wrap them in `lib.mkMerge` or `lib.mkIf`.

## Next Steps

- [NixOS Modules](03-nixos-modules.md) -- system aggregator details
- [Home Manager](04-home-manager.md) -- HM aggregator details
- [Reference](06-reference.md) -- validation commands and [introspection](06-reference.md#introspection)
