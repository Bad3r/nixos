{ config, lib, ... }:
{
  configurations.nixos.tpnix.module = {
    services.gnome.gnome-keyring.enable = true;
    security.pam.services = {
      login.enableGnomeKeyring = true;
      lightdm.enableGnomeKeyring = true;
      lightdm-autologin.enableGnomeKeyring = true;
    };
    home-manager.sharedModules = lib.mkAfter [ config.flake.homeManagerModules.gnomeKeyringBackend ];
  };
}
