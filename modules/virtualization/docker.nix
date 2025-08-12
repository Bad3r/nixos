# docker.nix - Docker containerization platform

{ config, ... }:
{
  flake.modules.nixos.workstation = {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = false;
    };
    users.extraGroups.docker.members = [ config.flake.meta.owner.username ];
  };
}
