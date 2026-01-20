/*
  Package: htop
  Description: Interactive process viewer for Unix systems.
  Homepage: https://htop.dev/
*/

_: {
  flake.homeManagerModules.apps.htop =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "htop" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.htop = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
