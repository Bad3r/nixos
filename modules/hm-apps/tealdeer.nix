/*
  Package: tealdeer
  Description: Fast tldr client written in Rust for command-line help pages.
  Homepage: https://github.com/dbrgn/tealdeer
*/

_: {
  flake.homeManagerModules.apps.tealdeer =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "tealdeer" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.tealdeer = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
