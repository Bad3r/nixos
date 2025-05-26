# modules/sudo.nix

{ config, ... }:
{
  flake.modules.nixos.pc = {
    security.sudo-rs.enable = true; # replace sudo with memory-safe sudo-rs
    users.users.${config.flake.meta.owner.username}.extraGroups = [ "wheel" ];
  };
}
