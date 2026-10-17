# Custom package overlays

A user-facing in-tree package reaches `pkgs` through one overlay module per package under `modules/custom-overlays/`, named after the package:

```nix
_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."my-new-package".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "my-new-package" = final.callPackage ../../packages/my-new-package { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."my-new-package" = Overlay;
}
```

`modules/hosts/common/custom-overlays-base.nix` imports every module registered under `flake.customOverlays.*`.
Each overlay gates itself on the matching `programs.<name>.extended.enable` option, so the package joins `pkgs` only where the app's row turns it on.
The package is then `pkgs.my-new-package` on every host whose row is on; rows are in [App registry](apps-module-registry.md).

A custom overlay is only for packages that must exist in `pkgs` for host builds or app modules.
A package used inside one module alone, with no need for a reusable `pkgs.<name>` attribute, can be a local `pkgs.callPackage ../../packages/<name> { }` in that module.

## Flake outputs

A derivation that is not user-facing and is exposed as a flake output registers through a `perSystem` module under `modules/packages/` instead:

```nix
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.my-tool = pkgs.callPackage ../../packages/my-tool { };
    };
}
```

## Building an overlay package

Overlay-backed packages are not top-level flake outputs, so `nix build .#my-package` fails with `does not provide attribute packages.x86_64-linux.my-package`.
Build through a host's `pkgs`, which applies the host overlays:

```sh
nix build "path:.#nixosConfigurations.<host>.pkgs.my-package"
```

New app and overlay modules must be tracked before that evaluation:

```sh
git add -N packages/my-package/default.nix modules/apps/my-package.nix modules/custom-overlays/my-package.nix
```
