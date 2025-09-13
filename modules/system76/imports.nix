{ config, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports =
      (with config.flake.nixosModules; [
        workstation
        nvidia-gpu
        roles.dev
      ])
      ++ [
        config.flake.nixosModules."warp-client"
        inputs.nixos-hardware.nixosModules.system76
      ];
  };
}
