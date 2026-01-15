# i3status-rust configuration
{
  flake.homeManagerModules.gui =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (config.gui.i3) netInterface;

      netBlockBase = {
        block = "net";
        interval = 2;
        format = " $icon {$ssid|$device} $ip ";
        format_alt = "  $speed_down.eng(prefix:K)/s  $speed_up.eng(prefix:K)/s ";
      };

      netBlock = netBlockBase // lib.optionalAttrs (netInterface != null) { device = netInterface; };

      i3statusBlocks = [
        netBlock
        {
          block = "disk_space";
          path = "/";
          info_type = "available";
          alert_unit = "GB";
          interval = 20;
          warning = 15.0;
          alert = 10.0;
          format = " $icon $available.eng(w:2) ";
          format_alt = " $icon $used.eng(w:2) / $total.eng(w:2) ";
        }
        {
          block = "memory";
          format = " $icon $mem_total_used_percents.eng(w:2) ";
          format_alt = " $icon_swap $swap_used_percents.eng(w:2) ";
        }
        {
          block = "cpu";
          interval = 1;
          format = " $icon $utilization ";
        }
        {
          block = "load";
          interval = 1;
          format = " $icon $1m ";
        }
        {
          block = "temperature";
          interval = 10;
          format = " $icon $max ";
        }
        {
          block = "sound";
          format = " $icon {$volume|muted} ";
          show_volume_when_muted = false;
        }
        {
          block = "battery";
          interval = 30;
          format = " $icon $percentage ";
        }
        {
          block = "time";
          interval = 60;
          format = " $icon $timestamp.datetime(f:'%a %d/%m %R') ";
        }
      ];

      i3statusBarConfig =
        let
          stylixThemeOverrides = lib.attrByPath [ "lib" "stylix" "i3status-rust" "bar" ] { } config;
        in
        {
          blocks = i3statusBlocks;
          settings = {
            icons = {
              icons = "awesome6";
            };
          }
          // lib.optionalAttrs (stylixThemeOverrides != { }) {
            theme = {
              theme = "plain";
              overrides = stylixThemeOverrides;
            };
          };
        };
    in
    {
      config = {
        programs.i3status-rust = {
          enable = true;
          bars.default = i3statusBarConfig;
        };

        xdg.configFile."i3status-rust/config.toml".source =
          config.xdg.configFile."i3status-rust/config-default.toml".source;
      };
    };
}
