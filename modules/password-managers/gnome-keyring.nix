_:
let
  mkHomeModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.pass-secret-service;
    in
    {
      services = {
        pass-secret-service.enable = lib.mkForce true;
        gnome-keyring.enable = lib.mkForce false;
      };

      systemd.user.services.pass-secret-service.Install.Alias = lib.mkIf cfg.enable [
        "dbus-org.freedesktop.secrets.service"
      ];
    };
in
{
  flake.homeManagerModules.base = mkHomeModule;
}
