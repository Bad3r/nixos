/*
  Package: zoxide
  Description: Smarter cd command with learning capabilities.
  Homepage: https://github.com/ajeetdsouza/zoxide
*/

_: {
  flake.homeManagerModules.apps.zoxide =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "zoxide" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.zoxide = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
