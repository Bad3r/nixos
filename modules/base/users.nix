{ config, lib, ... }:
{
  flake.nixosModules.base = _: {
    # Extend the owner's user account with additional groups
    users.users.${config.flake.lib.meta.owner.username} = {

      # Additional base groups that the user should be in
      extraGroups = lib.mkAfter [
        "wheel" # Admin privileges
        "networkmanager" # Network configuration
        "audio" # Audio devices
        "video" # Video devices
        "dialout" # Serial ports
        "render" # GPU acceleration
      ];

      # SSH authorized keys for remote access
      openssh.authorizedKeys.keys = config.flake.lib.meta.owner.sshKeys;
    };
  };
}
