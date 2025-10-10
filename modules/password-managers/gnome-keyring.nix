{ lib, ... }:
let
  mkSystemModule = _: {
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    security.pam.services.login.enableGnomeKeyring = lib.mkForce false;
  };

  mkHomeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.pass-secret-service;
      passPkg = cfg.package or pkgs.pass-secret-service;
      aliasFile = "${passPkg}/share/systemd/user/dbus-org.freedesktop.secrets.service";
    in
    {
      services = {
        pass-secret-service.enable = lib.mkForce true;
        gnome-keyring.enable = lib.mkForce false;
      };

      xdg.configFile."systemd/user/dbus-org.freedesktop.secrets.service" = lib.mkIf cfg.enable {
        source = aliasFile;
      };
    };
in
{
  flake.nixosModules.workstation = mkSystemModule;
  flake.homeManagerModules.base = mkHomeModule;
}
