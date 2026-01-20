/*
  Package: lutris
  Description: Open gaming platform for Linux.
  Homepage: https://lutris.net/
*/

_: {
  flake.homeManagerModules.apps.lutris =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "lutris" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.lutris = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
