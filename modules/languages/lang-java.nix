{ config, ... }:
{
  flake.nixosModules.lang.java.imports = with config.flake.nixosModules.apps; [
    temurin-bin-24
  ];
}
