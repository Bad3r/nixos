/*
  Package: gcc
  Description: GNU Compiler Collection.
  Homepage: https://gcc.gnu.org/
*/

_: {
  flake.homeManagerModules.apps.gcc =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "gcc" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.gcc = {
          enable = true;
          package = null; # Package installed by NixOS module
        };
      };
    };
}
