{ config, ... }:
{
  flake = {
    lib.meta.owner = {
      username = "vx";
      email = "bad3r@unsigned.sh";
      name = "Bad3r";
      matrix = "@bad3r:matrix.org";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj4fDeDKrAatG6IW5aEgA4ym8l+hj/r7Upeos11Gqu5 bad3r@unsigned.sh"
      ];
    };

    nixosModules = {
      base = {
        users.users.${config.flake.lib.meta.owner.username} = {
          isNormalUser = true;
          initialPassword = "";
          # User-specific groups that should follow the owner across all hosts
          extraGroups = [
            "input"
            "wheel"
            "networkmanager"
            "docker"
            "libvirtd"
          ];
        };

        nix.settings.trusted-users = [ config.flake.lib.meta.owner.username ];
      };
    };
  };
}
