{ config, ... }:
{
  configurations.nixos.system76.module = {
    imports = with config.flake.nixosModules; [
      base
      ssh
    ];
  };
}
