{ config, ... }:
{
  flake.nixosModules.lang.java.imports =
    let
      inherit (config.flake.nixosModules) apps;
    in
    [
      apps.temurin-bin-25
    ];
}
