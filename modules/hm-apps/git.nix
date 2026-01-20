/*
  Package: git
  Description: Distributed version control system.
  Homepage: https://git-scm.com/
*/

_: {
  flake.homeManagerModules.apps.git =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "git" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.git = {
          enable = true;
          # Package installed by NixOS module (not overridable here)
        };
      };
    };
}
