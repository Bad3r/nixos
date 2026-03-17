{ lib, ... }:
{
  configurations.nixos.system76.module = {
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    security.pam.services.login.enableGnomeKeyring = lib.mkForce false;
  };
}
