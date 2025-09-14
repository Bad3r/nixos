{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
in
{
  flake.nixosModules.lang.java.imports = getApps [
    "temurin-bin-24"
  ];
}
