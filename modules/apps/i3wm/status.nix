# i3status-rust configuration
# Configures the status bar with system metrics, media controls, and theming
{
  flake.homeManagerModules.apps.i3-config =
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
        format = " $icon {$ssid $signal_strength|$device} {$ip|} ";
        format_alt = " $icon $device ^icon_net_down $speed_down.eng(prefix:K)/s ^icon_net_up $speed_up.eng(prefix:K)/s ";
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
          info = 81.0;
          warning = 90.0;
          format = " $icon $max ";
          format_alt = " $icon $min min, $average avg, $max max ";
        }
        {
          block = "backlight";
          step_width = 10.0;
          minimum = 1.0;
          missing_format = "";
        }
        {
          block = "sound";
          driver = "pipewire";
          format = " $icon {$volume|muted} ";
          format_alt = " $icon $output_description.str(max_w:18) {$volume|muted} ";
          step_width = 2;
          max_vol = 100;
          headphones_indicator = true;
          show_volume_when_muted = false;
          click = [
            {
              button = "left";
              cmd = "pwvucontrol";
            }
          ];
        }
        {
          block = "privacy";
          driver = [
            {
              name = "v4l";
            }
            {
              name = "pipewire";
            }
          ];
        }
        {
          block = "battery";
          interval = 30;
          format = " $icon $percentage {$time_remaining.dur(hms:true, min_unit:m) |}";
          full_format = " $icon $percentage ";
          not_charging_format = " $icon $percentage ";
          missing_format = "";
        }
        {
          block = "notify";
          driver = "dunst";
          format = " $icon {$notification_count.eng(w:1)|} ";
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
