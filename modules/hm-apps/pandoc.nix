/*
  Package: pandoc
  Description: Universal document converter supporting many markup formats.
  Homepage: https://pandoc.org/
*/

_: {
  flake.homeManagerModules.apps.pandoc =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "pandoc" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.pandoc = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
