# Dependency Injection Pattern - Receiving Side
#
# This module receives metaOwner via the function parameter pattern: { metaOwner, ... }
# instead of importing it directly from a file path.
#
# The metaOwner parameter is injected by the system configuration via:
#   _module.args.metaOwner = metaOwner;
#
# See: modules/configurations/nixos.nix (_module.args block) for the injection point
{ lib, metaOwner, ... }:
{
  flake = {
    lib.meta.owner = metaOwner;

    nixosModules = {
      base = {
        # Define groups that may not exist by default
        users.groups = {
          ${metaOwner.group}.gid = metaOwner.gid;
          plugdev = { }; # For removable devices and USB access
          bluetooth = { }; # For Bluetooth device access
          netdev = { }; # For network device management (avahi SetHostName)
          power = { }; # Power management group (thermald D-Bus control where thermald is enabled)
        };

        users.users.${metaOwner.username} = {
          isNormalUser = true; # Changed from isSystemUser - this is an interactive user
          inherit (metaOwner) uid group;
          initialHashedPassword = "$y$j9T$XpFjwEnrrlkXEQpySrmJf0$Hrzam.8Q.oY2GI16bC8XdONqW.rTjfmhABU2Q.bDSZ1";
          # isNormalUser auto-sets: createHome=true, home="/home/${username}", useDefaultShell=true

          extraGroups = lib.mkAfter [
            "wheel" # Admin privileges
            "networkmanager" # Network configuration
            "render" # GPU acceleration
            "lp" # Printers and USB devices
            "systemd-journal" # Read journalctl without sudo
            "adm" # Read /var/log files without sudo
          ];

          # SSH authorized keys for remote access
          openssh.authorizedKeys.keys = metaOwner.sshKeys;
        };
      };
    };
  };
}
