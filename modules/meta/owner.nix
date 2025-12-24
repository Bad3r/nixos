{ lib, metaOwner, ... }:
{
  flake = {
    lib.meta.owner = metaOwner;

    nixosModules = {
      base = {
        # Define groups that may not exist by default
        users.groups = {
          plugdev = { }; # For removable devices and USB access
          bluetooth = { }; # For Bluetooth device access
        };

        users.users.${metaOwner.username} = {
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
          openssh.authorizedKeys.keys = metaOwner.sshKeys;
        };

        nix.settings.trusted-users = [ metaOwner.username ];
      };
    };
  };
}
