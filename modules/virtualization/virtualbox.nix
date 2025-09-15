{ config, ... }:
{
  flake.nixosModules.workstation = _: {
    config.virtualisation.virtualbox.host.enable = true;
    config.users.extraGroups.vboxusers.members = [ config.flake.lib.meta.owner.username ];
  };
}
