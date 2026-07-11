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

      # _main calls asyncio.get_event_loop(); Python 3.14 removed its implicit
      # loop-factory behavior, so it raises "no current event loop" and the unit
      # crash-loops into start-limit-hit. Upstream (mdellweg/pass_secret_service)
      # is dormant since 2023-12 and nixpkgs ships no fix. Drop once either does.
      package = pkgs.pass-secret-service.overridePythonAttrs (prev: {
        postPatch = (prev.postPatch or "") + ''
          substituteInPlace pass_secret_service/pass_secret_service.py \
            --replace-fail \
              'mainloop = asyncio.get_event_loop()' \
              'mainloop = asyncio.new_event_loop(); asyncio.set_event_loop(mainloop)'
        '';
      });
    in
    {
      home.packages = lib.mkBefore [ pkgs.pass ];
      services.pass-secret-service = {
        enable = true;
        inherit package;
      };

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
