/*
  Package: nix-index
  Description: Quickly locate nix packages with specific files.
  Homepage: https://github.com/nix-community/nix-index
*/

_: {
  flake.homeManagerModules.apps.nix-index =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "nix-index" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.nix-index = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
