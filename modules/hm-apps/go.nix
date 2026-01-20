/*
  Package: go
  Description: Go programming language compiler and tools.
  Homepage: https://go.dev/
*/

_: {
  flake.homeManagerModules.apps.go =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "services" "go" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.go = {
          enable = true;
          package = null; # Package installed by NixOS module
        };
      };
    };
}
