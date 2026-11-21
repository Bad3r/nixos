/*
  Package: activitywatch
  Description: Open-source automated time tracker.
  Homepage: https://activitywatch.net
  Documentation: https://docs.activitywatch.net
  Repository: https://github.com/ActivityWatch/activitywatch

  Summary:
    * Records the active window and keyboard/mouse idle state into a local database and charts it in a web UI.
    * Serves the UI from aw-server on 127.0.0.1:5600; this module reaches it at http://activitywatch.internal.

  Notes:
    * The hostname is a /etc/hosts entry on loopback; .internal names skip mDNS, which answers .local first.
    * A systemd-socket-proxyd unit forwards 127.0.0.1:80 to the server port, so the URL needs no port.
*/
_:
let
  ActivitywatchModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.activitywatch.extended;
    in
    {
      options.services.activitywatch.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable activitywatch.";
        };

        package = lib.mkPackageOption pkgs "activitywatch" { };

        hostname = lib.mkOption {
          type = lib.types.str;
          default = "activitywatch.internal";
          description = "Name that resolves to the loopback web UI.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 5600;
          description = "Port of aw-server on 127.0.0.1.";
        };
      };

      config = lib.mkIf cfg.enable {
        networking.hosts."127.0.0.1" = [ cfg.hostname ];

        systemd.sockets.activitywatch-http = {
          description = "ActivityWatch web UI on port 80";
          wantedBy = [ "sockets.target" ];
          listenStreams = [ "127.0.0.1:80" ];
        };

        systemd.services.activitywatch-http = {
          description = "ActivityWatch web UI proxy";
          serviceConfig = {
            ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd --exit-idle-time=10min 127.0.0.1:${toString cfg.port}";
            DynamicUser = true;
            IPAddressDeny = "any";
            IPAddressAllow = "localhost";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            CapabilityBoundingSet = "";
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            SystemCallFilter = [ "@system-service" ];
          };
        };
      };
    };
in
{
  flake.nixosModules.apps.activitywatch = ActivitywatchModule;
}
