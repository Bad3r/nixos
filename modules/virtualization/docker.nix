{ config, ... }:
{
  flake.nixosModules.workstation = _: {
    config.virtualisation.docker = {
      enable = true;
      enableOnBoot = false;
      # NVIDIA container integration is handled by hardware.nvidia-container-toolkit
    };
    config.users.extraGroups.docker.members = [ config.flake.lib.meta.owner.username ];
  };
}
