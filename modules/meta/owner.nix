{ lib, ... }:
let
  owner = import ../../lib/meta-owner-profile.nix;
in
{
  flake = {
    lib.meta.owner = owner;

    nixosModules = {
      base = {
        users.users.${owner.username} = {
          isNormalUser = true; # Changed from isSystemUser - this is an interactive user
          uid = 1000;
          initialPassword = "";
          # isNormalUser auto-sets: group="users", createHome=true, home="/home/${username}", useDefaultShell=true

          # All groups the user needs (merged from base/users.nix)
          extraGroups = lib.mkAfter [
            "wheel" # Admin privileges
            "networkmanager" # Network configuration
            "audio" # Audio devices
            "video" # Video devices
            "dialout" # Serial ports
            "render" # GPU acceleration
          ];

          # SSH authorized keys for remote access
          openssh.authorizedKeys.keys = owner.sshKeys;
        };

        nix.settings.trusted-users = [ owner.username ];
      };
    };
  };
}
