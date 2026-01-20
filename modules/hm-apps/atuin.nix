/*
  Package: atuin
  Description: Encrypted, synchronized shell history manager with powerful search.
  Homepage: https://atuin.sh/
*/

_: {
  flake.homeManagerModules.apps.atuin =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "atuin" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.atuin = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
