{ config, ... }:
{
  flake.nixosModules.workstation.imports = with config.flake.nixosModules; [
    pc
    ssh-askpass-fullscreen
  ];
}
