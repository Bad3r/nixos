{ config, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports =
      with config.flake.modules.nixos;
      [
        workstation
        roles.warp-client
        nvidia-gpu
      ]
      ++ [
        inputs.nixos-hardware.nixosModules.system76
      ];
  };
}
