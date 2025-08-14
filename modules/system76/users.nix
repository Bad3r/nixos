{ config, ... }:
let
  username = config.flake.meta.owner.username;
in
{
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      # Additional groups for system76 hardware and features
      # The base user is defined in base/users.nix
      users.users.${username}.extraGroups = lib.mkAfter [
        "docker" # Docker containers
        "libvirtd" # Virtualization
        "scanner" # Scanner access
        "lp" # Printing
      ];
    };
}
