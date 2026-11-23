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
    * The hostname is a networking.loopbackSites entry; .internal names skip mDNS, which answers .local first.
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
        networking.loopbackSites.${cfg.hostname} = {
          upstream = "http://127.0.0.1:${toString cfg.port}";
          # aw-server answers only Host values of 127.0.0.1 or localhost.
          hostHeader = "127.0.0.1";
        };
      };
    };
in
{
  flake.nixosModules.apps.activitywatch = ActivitywatchModule;
}
