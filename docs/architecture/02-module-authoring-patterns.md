# Authoring Patterns

The shapes a module under `modules/` takes, each shown with a file from the tree; placement and pitfalls are in [Module Authoring](02-module-authoring.md).

## Module That Needs `pkgs`

```nix
# modules/hosts/common/dbus.nix
{ lib, ... }:
let
  body =
    { pkgs, ... }:
    {
      services.dbus = {
        enable = true;
        packages = lib.mkAfter [ pkgs.dconf ];
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
```

flake-parts does **not** provide `pkgs` at the file's top level.
The exported value must be a function that receives `{ pkgs, ... }`.

## Module Without `pkgs`

```nix
# modules/boot/compression.nix
{
  flake.nixosModules.base = {
    boot.initrd.compressor = "zstd";
  };
}
```

A module that needs no extra arguments returns an attribute set directly.

## Multi-Namespace Module

```nix
# modules/stylix/stylix.nix (excerpt)
{ inputs, lib, ... }:
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

One file can populate both aggregators; keep the scopes independent.

## Extending Existing Namespaces

```nix
# modules/base/nix-settings.nix (excerpt)
{ lib, ... }:
let
  clientSettings = {
    # ...
  };
  settings = clientSettings // {
    # ...
  };
in
{
  config = {
    nix.settings = settings;
    flake.nixosModules.base.nix = {
      inherit settings;
    };

    flake.homeManagerModules.base = _: {
      nix.settings = clientSettings;
    };
  };
}
```

`lib.mkIf`, `lib.mkMerge`, and the other option helpers extend shared modules without clobbering their defaults.
General Nix daemon and evaluator settings stay in `modules/base/nix-settings.nix`.
Root is the only trusted Nix user, so the daemon ignores restricted settings from `NIX_CONFIG`, a user `nix.conf`, or `--option`, with one warning each.
A daemon setting takes effect only through `nix.settings`, and Home Manager writes only `clientSettings` to the user `nix.conf`.
Repairs, extra substituters or keys, and imports of unsigned paths run under `sudo`, as [Nix store maintenance](../troubleshooting/nix-store-maintenance.md) does.
Cache topology and download retry settings belong in `.github/actions/install-lix/substituters.conf`, which `modules/hosts/common/nix-substituters.nix` applies to every common host.

## Host Module

```nix
# modules/hosts/songbird/host-id.nix (simplified)
_: {
  configurations.nixos.songbird.module = {
    networking.hostId = "<first 8 hex digits of /etc/machine-id>";
  };
}
```

[Host Composition](05-host-composition.md) covers how host modules assemble.
