{ config, ... }:
{
  flake.modules.nixos.workstation = {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = false;
      enableNvidia = false; # NVIDIA support handled by nvidia-gpu module if needed
    };
    users.extraGroups.docker.members = [ config.flake.meta.owner.username ];
  };
}
