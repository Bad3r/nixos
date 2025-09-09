{ config, ... }:
{
  configurations.nixos.tec.module = {
    imports = (with config.flake.nixosModules; [ workstation ]) ++ [
      config.flake.nixosModules."warp-client"
    ];
  };
}
