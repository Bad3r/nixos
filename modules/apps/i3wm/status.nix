# i3status-rust configuration
# Configures the status bar with system metrics, media controls, and theming
{ config, ... }:
let
  inherit (config.flake.lib) octicons;
in
{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      osConfig,
      pkgs,
      lib,
      ...
    }:
    let
      inherit (config.gui.i3) netInterface;
      stylixColors = config.lib.stylix.colors.withHashtag;
      appRows = import ./_app-rows.nix { inherit lib osConfig pkgs; };

      # En spaces between blocks, a thin space after each icon.
      thin = builtins.fromJSON ''"\u2009"'';
      en = builtins.fromJSON ''"\u2002"'';
      pad = text: en + text + en;

      netBlockBase = {
        block = "net";
        interval = 2;
        format = pad "$icon${thin}$device ^icon_net_down${thin}$speed_down.eng(prefix:K)/s ^icon_net_up${thin}$speed_up.eng(prefix:K)/s";
        format_alt = pad "$icon${thin}{$ssid $signal_strength|$device} {$ip|}";
      };

      netBlock = netBlockBase // lib.optionalAttrs (netInterface != null) { device = netInterface; };

      i3statusBlocks = [
        netBlock
        {
          block = "uptime";
          interval = 3600;
          format = pad "$icon${thin}$uptime";
        }
        {
          block = "disk_space";
          path = "/";
          info_type = "available";
          alert_unit = "GB";
          interval = 20;
          warning = 15.0;
          alert = 10.0;
          format = pad "$icon${thin}$available.eng(w:2)";
          format_alt = pad "$icon${thin}$used.eng(w:2) / $total.eng(w:2)";
        }
        {
          block = "memory";
          format = pad "$icon${thin}$mem_total_used_percents.eng(w:2)";
          format_alt = pad "$icon_swap${thin}$swap_used_percents.eng(w:2)";
        }
        {
          block = "cpu";
          interval = 1;
          format = pad "$icon${thin}$utilization";
        }
        {
          block = "nvidia_gpu";
          interval = 2;
          # Temperature states; plain until 75 °C.
          idle = 75;
          good = 80;
          info = 85;
          warning = 90;
          format = pad "$icon${thin}$utilization.eng(w:2) $memory.eng(w:3,p:Gi)";
        }
        {
          block = "load";
          interval = 1;
          format = pad "$icon${thin}$1m";
        }
        {
          block = "temperature";
          interval = 10;
          # Normal load stays plain.
          idle = 75.0;
          info = 81.0;
          warning = 90.0;
          format = pad "$icon${thin}$max";
          format_alt = pad "$icon${thin}$min min, $average avg, $max max";
        }
        {
          block = "sound";
          driver = "pipewire";
          format = pad "$icon${thin}{$volume|muted}";
          format_alt = pad "$icon${thin}$output_description.str(max_w:18) {$volume|muted}";
          step_width = 2;
          max_vol = 100;
          headphones_indicator = true;
          show_volume_when_muted = false;
          click = [
            {
              button = "left";
              cmd = lib.getExe (appRows.package "pwvucontrol");
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
          format = lib.concatMapStrings (source: "{${pad "$icon_${source}"}|}") [
            "audio"
            "audio_sink"
            "video"
            "webcam"
            "unknown"
          ];
        }
        {
          block = "battery";
          interval = 30;
          format = pad "$icon${thin}$percentage{ $time_remaining.dur(hms:true, min_unit:m)|}";
          full_format = pad "$icon${thin}$percentage";
          not_charging_format = pad "$icon${thin}$percentage";
          missing_format = "";
        }
        {
          block = "notify";
          driver = "dunst";
          format = pad "$icon{${thin}$notification_count.eng(w:1)|}";
        }
        {
          block = "time";
          interval = 60;
          # Time brighter than the date.
          format = pad "$icon${thin}$timestamp.datetime(f:'%a %d/%m') <span color='${stylixColors.base05}'>$timestamp.datetime(f:'%R')</span>";
          click = [
            {
              button = "left";
              # gsimplecal-dropdown (config.nix) toggles the calendar, positions
              # it flush under the clock, and auto-closes it after the pointer
              # leaves (gui.i3.calendarAutocloseSeconds).
              cmd = "gsimplecal-dropdown";
            }
          ];
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
              # Octicons over Font Awesome; headphones, microphones, and batteries stay Font Awesome.
              icons = "awesome6";
              overrides = octicons.status;
            };
            # Icons at about base03 on idle blocks, still legible on warning colors.
            icons_format = "<span fgalpha='63%'>{icon}</span>";
          }
          // lib.optionalAttrs (stylixThemeOverrides != { }) {
            theme = {
              theme = "plain";
              # VS Code status bar: dim text on base01, no dividers.
              overrides = stylixThemeOverrides // {
                separator = "";
                idle_bg = stylixColors.base01;
                idle_fg = stylixColors.base04;
                good_bg = stylixColors.base01;
                good_fg = stylixColors.base05;
                separator_bg = stylixColors.base01;
                separator_fg = stylixColors.base02;
              };
            };
          };
        };
    in
    {
      config = {
        programs.i3status-rust = {
          enable = appRows.enabled "i3status-rust";
          package = appRows.package "i3status-rust";
          bars.default = i3statusBarConfig;
        };

        xdg.configFile."i3status-rust/config.toml" = lib.mkIf config.programs.i3status-rust.enable {
          source = config.xdg.configFile."i3status-rust/config-default.toml".source;
        };
      };
    };
}
