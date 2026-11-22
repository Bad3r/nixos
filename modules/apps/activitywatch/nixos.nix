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
    * nginx on 127.0.0.1:80 proxies the hostname to the server, so the URL needs no port.
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
      loopbackHttp = {
        addr = "127.0.0.1";
        port = 80;
      };
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

        services.nginx = {
          enable = true;
          virtualHosts = {
            # Closes requests for any other name, so a DNS-rebinding page
            # cannot reach the server through the Host rewrite below.
            activitywatch-reject = {
              default = true;
              serverName = "_";
              listen = [ loopbackHttp ];
              locations."/".return = "444";
            };

            ${cfg.hostname} = {
              listen = [ loopbackHttp ];
              locations."/" = {
                proxyPass = "http://127.0.0.1:${toString cfg.port}";
                recommendedProxySettings = false;
                # aw-server answers only Host values of 127.0.0.1 or localhost.
                extraConfig = "proxy_set_header Host 127.0.0.1;";
              };
            };
          };
        };
      };
    };
in
{
  flake.nixosModules.apps.activitywatch = ActivitywatchModule;
}
