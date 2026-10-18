# Custom package overlays

A user-facing in-tree package at `packages/<name>/default.nix` becomes `pkgs.<name>` on every host whose `<name>` app row is on.
`modules/hosts/common/custom-overlays-base.nix` derives that overlay for every `packages/` directory named after an app registered under `flake.nixosModules.apps`, so the package directory and the app module are the only files to create.
The derived overlay calls `final.callPackage` on the directory with no arguments and gates itself on `programs.<name>.extended.enable`; rows are in [App registry](apps-module-registry.md).

A package that needs more, such as a `callPackage` argument or a patch on a nixpkgs package, registers its own overlay module as `flake.customOverlays.<name>`, which takes the place of a derived one:

```nix
_: {
  flake.customOverlays.my-package =
    { config, lib, ... }:
    {
      config = lib.mkIf config.programs.my-package.extended.enable {
        nixpkgs.overlays = [
          (_final: prev: {
            my-package = prev.my-package.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [ ./my-package-fix.patch ];
            });
          })
        ];
      };
    };
}
```

`modules/hosts/common/custom-overlays-base.nix` imports every module registered under `flake.customOverlays.*` into each host.

A package used inside one module alone needs no `pkgs.<name>` attribute.
Its directory name matches no app, so it gets no overlay, and the module calls `pkgs.callPackage ../../packages/<name> { }` itself.

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

New package and app files must be tracked before a `git+file` evaluation:

```sh
git add -N packages/my-package/default.nix modules/apps/my-package.nix
```
