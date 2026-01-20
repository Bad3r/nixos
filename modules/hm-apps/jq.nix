/*
  Package: jq
  Description: Lightweight command-line JSON processor.
  Homepage: https://jqlang.github.io/jq/
*/

_: {
  flake.homeManagerModules.apps.jq =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "jq" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.jq = {
          enable = true;
          package = null; # Package installed by NixOS module
        };
      };
    };
}
