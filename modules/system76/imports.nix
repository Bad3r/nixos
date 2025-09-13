{ config, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports =
      (with config.flake.nixosModules; [
        workstation
        nvidia-gpu
      ])
      ++ [
        config.flake.nixosModules.roles."dev-fhs"
        config.flake.nixosModules."warp-client"
        inputs.nixos-hardware.nixosModules.system76
      ];
  };
}
