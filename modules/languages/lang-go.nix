{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
in
{
  flake.nixosModules.lang.go.imports = getApps [
    "go"
  ];
}
