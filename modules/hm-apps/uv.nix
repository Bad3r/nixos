/*
  Package: uv
  Description: Extremely fast Python package installer and resolver.
  Homepage: https://docs.astral.sh/uv/
*/

_: {
  flake.homeManagerModules.apps.uv =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "uv" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.uv = {
          enable = true;
          package = null; # Package installed by NixOS module
        };
      };
    };
}
