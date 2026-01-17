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

      systemd.user.services.pass-secret-service = lib.mkIf cfg.enable {
        Unit = {
          After = [ "graphical-session.target" ];
          PartOf = lib.mkForce [ "graphical-session.target" ];
        };
        Service.Environment = [
          "DISPLAY=:0"
          "XAUTHORITY=%h/.Xauthority"
        ];
        Install = {
          Alias = [ "dbus-org.freedesktop.secrets.service" ];
          WantedBy = lib.mkForce [ "graphical-session.target" ];
        };
      };
    };
in
{
  flake.homeManagerModules.base = mkHomeModule;
}
