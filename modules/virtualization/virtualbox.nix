{ config, ... }:
{
  flake.nixosModules.workstation = {
    virtualisation.virtualbox.host.enable = true;
    users.extraGroups.vboxusers.members = [ config.flake.lib.meta.owner.username ];
  };
}
