/*
  Package: nh
  Description: Nix helper tool for common operations like switching and garbage collection.
  Homepage: https://github.com/viperML/nh
*/

_: {
  flake.homeManagerModules.apps.nh =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "nh" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.nh = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
