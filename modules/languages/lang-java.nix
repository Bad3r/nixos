{ config, ... }:
{
  flake.modules.nixos.lang.java.imports = with config.flake.modules.nixos.apps; [
    temurin-bin-24
  ];
}
