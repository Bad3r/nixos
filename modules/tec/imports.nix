{ config, ... }:
{
  configurations.nixos.tec.module = {
    imports = with config.flake.modules.nixos; [
      workstation
    ];
  };
}
