# modules/linux/services/dbus.nix
{ pkgs, ... }:

{
  services.dbus = {
    enable = true;
    packages = with pkgs; [ dconf ];
  };
}
