{ config, ... }:
{
  flake.nixosModules.workstation = _: {
    config.virtualisation.docker = {
      enable = true;
      enableOnBoot = false;
      enableNvidia = false; # NVIDIA support handled by nvidia-gpu module if needed
    };
    config.users.extraGroups.docker.members = [ config.flake.lib.meta.owner.username ];
  };
}
