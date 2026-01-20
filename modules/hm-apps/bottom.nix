/*
  Package: bottom
  Description: Cross-platform graphical process/system monitor.
  Homepage: https://github.com/ClementTsang/bottom
*/

_: {
  flake.homeManagerModules.apps.bottom =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "bottom" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.bottom = {
          enable = true;
          package = null; # Package installed by NixOS module
        };
      };
    };
}
