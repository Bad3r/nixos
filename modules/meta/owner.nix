{ config, ... }:
{
  flake = {
    lib.meta.owner = {
      username = "vx";
      email = "bad3r@unsigned.sh";
      name = "Bad3r";
      matrix = "@bad3r:matrix.org";
      sshKeys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIBBzWtUqOIpeaT+X+BvXKLZmhfevYbGDc0CLsuI3MfUdAAAABHNzaDo= bad3r@unsigned.sh"
      ];
    };

    nixosModules = {
      base = {
        users.users.${config.flake.lib.meta.owner.username} = {
          isNormalUser = true;
          initialPassword = "";

          extraGroups = [
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
