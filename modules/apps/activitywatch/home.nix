/*
  Package: activitywatch
  Description: Open-source automated time tracker.
  Homepage: https://activitywatch.net
  Documentation: https://docs.activitywatch.net
  Repository: https://github.com/ActivityWatch/activitywatch

  Summary:
    * Runs aw-server, aw-watcher-afk, and aw-watcher-window as Home Manager user services.
    * The window watcher reads X11 window properties; a Wayland session needs awatcher or aw-watcher-window-wayland.
    * Data stays in ~/.local/share/activitywatch; nothing leaves the machine.

  Config Options:
    exclude_apps: Window classes the window watcher drops entirely (regular expressions).
    exclude_titles: Window titles the window watcher blanks (regular expressions).
    cors: Origins besides 127.0.0.1 and localhost that the server accepts API calls from.
*/

_: {
  flake.homeManagerModules.apps.activitywatch =
    {
      osConfig,
      lib,
      ...
    }:
    let
      cfg = osConfig.services.activitywatch.extended;
      # The package's watcher units start at default.target, before the
      # session has a display, and never restart; bind them to the graphical
      # session instead. Its BindsTo on activitywatch.target would stop them
      # with that target and leave nothing to start them again.
      watcherUnit = {
        Unit = {
          BindsTo = lib.mkForce [ ];
          Wants = [ "activitywatch.service" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
      };
      portOptions = [
        "--port"
        (toString cfg.port)
      ];
    in
    {
      config = lib.mkIf cfg.enable {
        services.activitywatch = {
          enable = true;
          inherit (cfg) package;

          settings = {
            inherit (cfg) port;
            cors = [ "http://${cfg.hostname}" ];
          };

          # The watchers read a TOML file whose table carries the watcher name.
          watchers = {
            aw-watcher-afk = {
              inherit (cfg) package;
              extraOptions = portOptions;
            };

            aw-watcher-window = {
              inherit (cfg) package;
              extraOptions = portOptions;
              settings.aw-watcher-window = {
                exclude_apps = [
                  "(?i)1password"
                  "(?i)bitwarden"
                  "(?i)keepassxc"
                  "(?i)tor.?browser"
                  "(?i)^mpv$"
                ];
                exclude_titles = [
                  "(?i)private browsing"
                  "(?i)incognito"
                ];
              };
            };
          };
        };

        systemd.user.services = {
          activitywatch-watcher-aw-watcher-afk = watcherUnit;
          activitywatch-watcher-aw-watcher-window = watcherUnit;
        };
      };
    };
}
