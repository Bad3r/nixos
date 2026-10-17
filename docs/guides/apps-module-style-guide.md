# Apps Module Style Guide

Conventions for the NixOS app modules under `modules/apps/`, one program per file.
`modules/apps/ent.nix` is the canonical template, and [Architecture](../architecture/README.md) covers the aggregators and helpers around it.

- [Header block](apps-module-header.md): the top-of-file comment and the sources behind each field.
- [Package sources](apps-module-package-sources.md): nixpkgs, external flake input, and Python packages.
- [App registry](apps-module-registry.md): baseline rows, host rows, prerequisites, and package ownership.
- [Home Manager integration](apps-module-home-manager.md): the module that configures the program for the user.

## Scope

- Every NixOS app module exported under `flake.nixosModules.apps` follows these conventions.
- Repository-wide conventions are in [Module Authoring](../architecture/02-module-authoring.md).

## File layout

- Store each app module at `modules/apps/<tool>.nix` and export it as `flake.nixosModules.apps.<tool>`.
- Provide additional bundles, for example `base`, only when they are meaningful.
- Keep an app module to package enablement and lightweight configuration.
  Compose higher-level behaviour in a domain module, for example under `modules/networking/`.

## Module body

- The outer flake-parts module takes `_:`, or `{ inputs, ... }:` for a package from an external flake input.
- The NixOS module is a function of `{ config, lib, pkgs, ... }:` inside a `let` binding.
- `cfg = config.programs.<tool>.extended;` sits inside that function, not in the outer scope, which [The Two-Context Problem](../architecture/02-module-authoring.md#the-two-context-problem) explains.
- `enable` defaults to `false`, and `package` comes from `lib.mkPackageOption pkgs "<attr>" { }`.
- `environment.systemPackages = [ cfg.package ];` under `lib.mkIf cfg.enable` installs the program.
- Other configuration stays limited to what the app needs to function.
- An unfree package is declared as [Unfree packages](../architecture/03-nixos-modules.md#unfree-packages) describes.
- Attribute sets use two-space indentation.

## Namespace selection

Most apps use `programs.<name>.extended`; an app that needs a NixOS service, such as udev rules or a systemd unit, uses `services.<name>.extended`.

| Namespace                  | When to use             | Baseline block |
| -------------------------- | ----------------------- | -------------- |
| `programs.<name>.extended` | Package-only apps       | `programs`     |
| `services.<name>.extended` | Apps with NixOS service | `services`     |

The module shape is identical with `services` in the option paths, as in `modules/apps/thinkfan.nix`.

## Adding an app

1. Confirm the package attribute exists, as [Package sources](apps-module-package-sources.md) shows.

2. Copy `modules/apps/ent.nix` to `modules/apps/<tool>.nix`, set its `lib.mkPackageOption` to the actual package name, and write its [header block](apps-module-header.md).

3. Stage the new file, because a flake copies only tracked files and an untracked module fails with "option does not exist":

   ```sh
   git add modules/apps/<tool>.nix
   ```

4. Add its baseline row, as [App registry](apps-module-registry.md) describes.

5. When Home Manager has a module for the program, follow [Home Manager integration](apps-module-home-manager.md).

6. Format, check, and confirm the row from the repository root, expecting `bool`, `true`, and `true` for a row that is on:

   ```sh
   nix run path:.#treefmt -- .
   nix flake check path:. --accept-flake-config --no-build --offline
   nix eval --raw "path:.#nixosConfigurations.<host>.options.programs.<tool>.extended.enable.type.name"
   nix eval "path:.#nixosConfigurations.<host>.config.programs.<tool>.extended.enable"
   nix eval "path:.#nixosConfigurations.<host>.config.environment.systemPackages" --apply 'pkgs: builtins.any (p: p.pname or "" == "<tool>") pkgs'
   ```

Before pushing, run the validation suite in [Reference](../architecture/06-reference.md#validation).
