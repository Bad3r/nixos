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
    privacy_filter: Title patterns whose windows the window watcher drops entirely, whatever the window class.
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
      # session instead.
      watcherUnit = {
        Unit.PartOf = [ "graphical-session.target" ];
        Service = {
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
      };
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
            aw-watcher-afk.package = cfg.package;

            aw-watcher-window = {
              inherit (cfg) package;
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
                # Stash runs in a browser tab, so no window class identifies it; only its title does.
                privacy_filter = [
                  {
                    pattern = "(?i)\\bstash\\b";
                    action = "drop";
                  }
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
