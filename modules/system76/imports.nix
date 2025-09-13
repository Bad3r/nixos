{ config, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports =
      (with config.flake.nixosModules; [
        workstation
        nvidia-gpu
      ])
      ++ [
        config.flake.nixosModules."role-dev"
        config.flake.nixosModules."role-media"
        config.flake.nixosModules."role-net"
        config.flake.nixosModules."warp-client"
        inputs.nixos-hardware.nixosModules.system76
      ];
  };
}
