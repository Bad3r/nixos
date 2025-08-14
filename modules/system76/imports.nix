{ config, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports = with config.flake.modules.nixos; [
      workstation
      nvidia-gpu
    ] ++ [
      inputs.nixos-hardware.nixosModules.system76
    ];
  };
}
