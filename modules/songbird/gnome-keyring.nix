{ lib, ... }:
{
  configurations.nixos.songbird.module = {
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    security.pam.services.login.enableGnomeKeyring = lib.mkForce false;
  };
}
