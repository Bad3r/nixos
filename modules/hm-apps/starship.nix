/*
  Package: starship
  Description: Minimal, blazing-fast cross-shell prompt.
  Homepage: https://starship.rs/
*/

_: {
  flake.homeManagerModules.apps.starship =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "starship" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.starship = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
