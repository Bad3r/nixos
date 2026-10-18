# Apps module Home Manager integration

A program that Home Manager has a module for gets a second file, `modules/hm-apps/<tool>.nix`, exported as `flake.homeManagerModules.apps.<tool>`.
The NixOS row installs the program and switches the Home Manager module on; the Home Manager module only configures it.

## Home Manager support

Look for an upstream module in the local mirror, whose path is in [Local mirrors](../reference/local-mirrors.md):

```sh
ls /data/git/nix-community-home-manager/modules/programs/<tool>.nix
grep -r "programs\.<tool>" /data/git/nix-community-home-manager/modules/
```

Firefox derivatives share `/data/git/nix-community-home-manager/modules/programs/firefox/mkFirefoxModule.nix`.
Without an upstream module, the NixOS app module is the whole integration.

Then check whether the upstream package option is nullable:

```sh
grep -A3 "package.*=" /data/git/nix-community-home-manager/modules/programs/<tool>.nix
```

## Module

The file opens with the same header block as the NixOS module and gates its config on the NixOS row through `osConfig`:

```nix
_: {
  flake.homeManagerModules.apps.<tool> =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "<tool>" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.<tool> = {
          enable = true;
          package = null;
        };
      };
    };
}
```

`lib.attrByPath` with a `false` default reads the row even where `osConfig` lacks the option, and `lib.mkIf` delays the config so reading `osConfig` cannot recurse.

## Package

The NixOS row owns the package, so the Home Manager module never brings its own:

| Upstream package option | Home Manager module sets                 |
| ----------------------- | ---------------------------------------- |
| Nullable                | `package = null`; the row installs it    |
| Not nullable            | `package` from the row                   |
| None                    | Nothing; Home Manager only writes config |

The row's package is `lib.attrByPath [ "programs" "<tool>" "extended" "package" ] pkgs.<tool> osConfig`.
A Home Manager feature that needs the package reference, such as `enableGitIntegration` in `programs.bun`, also takes `package` from the row instead of `null`, with a comment naming the feature.

## Loading

Every module registered under `flake.homeManagerModules.apps` loads on every host, as [Home Manager](../architecture/04-home-manager.md#app-loading) describes, so the file is the only step.
The gate keeps a loaded module inert, so hosts differ only through their NixOS rows.
A module without a row gates on its own enable option, or on the NixOS setting it configures, as `i3-config` does with the i3 window manager.

## Theming

Check the Stylix mirror for a target:

```sh
grep -r "<tool>" /data/git/nix-community-stylix/modules/
ls /data/git/nix-community-stylix/modules/<tool>/
```

Target options beyond what `autoEnable` sets go in the `targets` block of `modules/stylix/stylix.nix`, which exports `flake.homeManagerModules.apps.stylix-gui`.
The target rules are in [Stylix Integration](stylix-integration.md).

## Browser extensions

Gecko browser extensions are not sourced from NUR.
`modules/browsers/_gecko-extension-data.nix` pins their IDs and AMO install URLs, and `modules/browsers/_gecko-extensions.nix` renders them into `ExtensionSettings` policies and per-profile extension lists.
