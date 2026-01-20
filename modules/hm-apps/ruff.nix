/*
  Package: ruff
  Description: Extremely fast Python linter and formatter.
  Homepage: https://docs.astral.sh/ruff/
*/

_: {
  flake.homeManagerModules.apps.ruff =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "ruff" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.ruff = {
          enable = true;
          package = null; # Package installed by NixOS module
          settings = { }; # Required - empty config
        };
      };
    };
}
