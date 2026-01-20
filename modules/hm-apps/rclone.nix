/*
  Package: rclone
  Description: Command-line cloud storage sync utility supporting many providers.
  Homepage: https://rclone.org/
*/

_: {
  flake.homeManagerModules.apps.rclone =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "rclone" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.rclone = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
