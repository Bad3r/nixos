_:
let
  mkHomeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.pass-secret-service;
    in
    {
      home.packages = lib.mkBefore [ pkgs.pass ];
      services.pass-secret-service.enable = true;

      systemd.user.services.pass-secret-service = lib.mkIf cfg.enable {
        Unit = {
          After = [ "graphical-session.target" ];
          PartOf = lib.mkForce [ "graphical-session.target" ];
          StartLimitBurst = 3;
          StartLimitIntervalSec = "1h";
        };
        Install = {
          Alias = [ "dbus-org.freedesktop.secrets.service" ];
          WantedBy = lib.mkForce [ "graphical-session.target" ];
        };
        Service = {
          Restart = "on-failure";
          RestartSec = 3;
        };
      };
    };
in
{
  flake.homeManagerModules.passSecretServiceBackend = mkHomeModule;
}
