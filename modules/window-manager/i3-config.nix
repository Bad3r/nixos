{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      commandsDefault = {
        launcher = "${lib.getExe pkgs.rofi} -modi drun -show drun";
        terminal = lib.getExe pkgs.kitty;
        browser = lib.getExe pkgs.firefox;
        emoji = "${lib.getExe pkgs.rofimoji} --selector rofi";
        playerctl = lib.getExe pkgs.playerctl;
        volume = lib.getExe pkgs.pamixer;
        brightness = lib.getExe pkgs.xorg.xbacklight;
        screenshot = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
      };
      stylixAvailable = config ? stylix && config.stylix ? targets && config.stylix.targets ? i3;
      stylixColors =
        if stylixAvailable then lib.attrByPath [ "lib" "stylix" "colors" ] null config else null;
      toLockColor =
        colorHex:
        let
          trimmed = lib.removePrefix "#" colorHex;
          normalized = if builtins.stringLength trimmed == 8 then trimmed else trimmed + "FF";
        in
        lib.strings.toUpper normalized;
      stylixLockPalette =
        if stylixColors != null then
          {
            background = toLockColor (lib.attrByPath [ "base00" ] "#262c36" stylixColors);
            ring = toLockColor (
              lib.attrByPath [ "base04" ] (lib.attrByPath [ "base05" ] "#768390" stylixColors) stylixColors
            );
            ringWrong = toLockColor (lib.attrByPath [ "base08" ] "#f47067" stylixColors);
            ringVerify = toLockColor (lib.attrByPath [ "base0B" ] "#57ab5a" stylixColors);
            line = toLockColor (
              lib.attrByPath [ "base03" ] (lib.attrByPath [ "base04" ] "#545d68" stylixColors) stylixColors
            );
            text = toLockColor (lib.attrByPath [ "base05" ] "#cdd9e5" stylixColors);
          }
        else
          null;
      defaultLockPalette = {
        background = "262C36FF";
        ring = "768390FF";
        ringWrong = "F47067FF";
        ringVerify = "57AB5AFF";
        line = "545D68FF";
        text = "CDD9E5FF";
      };
      lockPalette = if stylixLockPalette != null then stylixLockPalette else defaultLockPalette;
      lockScript = pkgs.writeShellApplication {
        name = "i3lock-stylix";
        runtimeInputs = [
          pkgs.i3lock-color
          pkgs.procps
          pkgs.xorg.xbacklight
        ];
        text = ''
          set -eu

          cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/i3lock"
          brightness_file="$cache_dir/brightness"

          restore_brightness() {
            if [ -f "$brightness_file" ]; then
              target=$(cat "$brightness_file")
              xbacklight -set "$target" >/dev/null 2>&1 || true
              rm -f "$brightness_file"
            fi
          }

          if pgrep -x i3lock-color > /dev/null; then
            exit 0
          fi

          mkdir -p "$cache_dir"
          restore_brightness

          exec i3lock-color \
            --color=${lockPalette.background} \
            --inside-color=${lockPalette.background} \
            --ring-color=${lockPalette.ring} \
            --insidewrong-color=${lockPalette.background} \
            --ringwrong-color=${lockPalette.ringWrong} \
            --insidever-color=${lockPalette.background} \
            --ringver-color=${lockPalette.ringVerify} \
            --line-color=${lockPalette.line} \
            --keyhl-color=${lockPalette.ringVerify} \
            --bshl-color=${lockPalette.ringWrong} \
            --time-color=${lockPalette.text} \
            --date-color=${lockPalette.text} \
            --layout-color=${lockPalette.text} \
            --time-str="%H:%M:%S" \
            --date-str="%A, %d %B %Y" \
            --radius=120 \
            --ring-width=10 \
            --clock "$@"
        '';
      };
      lockCommandDefault = lib.getExe lockScript;
      lockCommandValue = lib.attrByPath [ "gui" "i3" "lockCommand" ] lockCommandDefault config;
      i3Commands = lib.attrByPath [ "gui" "i3" "commands" ] commandsDefault config;
      netInterface = lib.attrByPath [ "gui" "i3" "netInterface" ] null config;
      netBlockBase = {
        block = "net";
        interval = 5;
        format = " $icon {$ssid|$device} $ip ";
        format_alt = " $icon  $speed_down.eng(prefix:K)/s  $speed_up.eng(prefix:K)/s ";
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
          format = " $icon $volume ";
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
              overrides = {
                cpu = "";
                update = "";
                temp = [
                  ""
                  ""
                  ""
                ];
                volume = [
                  ""
                  ""
                  ""
                ];
                volume_muted = "";
                bat = [
                  ""
                  ""
                  ""
                  ""
                  ""
                ];
                bat_charging = "";
                net_wireless = [
                  "▂"
                  "▃"
                  "▅"
                  "▇"
                  ""
                ];
                net_wired = "";
                net_down = "";
                net_up = "";
                net_vpn = "";
                net_loopback = "";
                net_unknown = "";
              };
            };
          }
          // lib.optionalAttrs (stylixThemeOverrides != { }) {
            theme = {
              theme = "plain";
              overrides = stylixThemeOverrides;
            };
          };
        };
      workspaceOutputAssign = [
        {
          workspace = "1";
          output = [ "DP-1" ];
        }
        {
          workspace = "2";
          output = [ "DP-1" ];
        }
        {
          workspace = "3";
          output = [ "DP-1" ];
        }
        {
          workspace = "4";
          output = [ "DP-1" ];
        }
        {
          workspace = "5";
          output = [ "DP-1" ];
        }
        {
          workspace = "6";
          output = [ "DP-1" ];
        }
        {
          workspace = "7";
          output = [ "eDP-1-1" ];
        }
        {
          workspace = "8";
          output = [ "HDMI-0" ];
        }
        {
          workspace = "9";
          output = [ "HDMI-0" ];
        }
        {
          workspace = "10";
          output = [ "HDMI-0" ];
        }
      ];
      baseExtraConfig = lib.concatStringsSep "\n" [
        "default_orientation horizontal"
        "popup_during_fullscreen smart"
        "new_window normal"
        "new_float normal"
        ""
      ];
    in
    {
      options.gui.i3 = {
        netInterface = lib.mkOption {
          description = "Primary network interface for the i3status net block.";
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "enp4s0";
        };

        lockCommand = lib.mkOption {
          description = "Command used to lock the screen within the i3 session.";
          type = lib.types.nullOr lib.types.str;
          default = lockCommandDefault;
          example = "i3lock";
        };

        commands = lib.mkOption {
          description = "Commonly used command strings that other i3 modules can reuse.";
          type = lib.types.attrsOf lib.types.str;
          default = commandsDefault;
          example = {
            launcher = "rofi -show drun";
            terminal = "kitty";
          };
        };
      };

      config = {
        home.packages = [
          pkgs.rofimoji
          lockScript
        ];

        programs.i3status-rust = {
          enable = true;
          bars.default = i3statusBarConfig;
        };

        stylix.targets.i3.enable = lib.mkDefault true;

        xdg.configFile = {
          "i3status-rust/config.toml".source =
            config.xdg.configFile."i3status-rust/config-default.toml".source;

          "i3/scripts/i3lock-stylix" = {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              exec ${lockCommandValue} "$@"
            '';
          };

          "i3/scripts/blur-lock" = {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              exec ${lockCommandValue} "$@"
            '';
          };
        };

        xsession = {
          enable = true;
          windowManager.i3 = {
            enable = true;
            config = {
              modifier = lib.mkDefault "Mod4";
              inherit (i3Commands) terminal;
              menu = i3Commands.launcher;

              floating = {
                modifier = "Mod1";
                border = 5;
                titlebar = false;
              };

              focus = {
                followMouse = true;
                newWindow = "focus";
              };

              window = {
                border = 5;
                hideEdgeBorders = "none";
                titlebar = false;
              };

              workspaceAutoBackAndForth = true;
              inherit workspaceOutputAssign;

              gaps = {
                inner = 0;
                outer = 4;
                top = 6;
                bottom = 6;
              };

              bars = [
                (
                  {
                    mode = "dock";
                    hiddenState = "hide";
                    position = "top";
                    trayOutput = "primary";
                    workspaceButtons = true;
                    workspaceNumbers = true;
                    statusCommand = lib.getExe pkgs.i3status-rust;
                  }
                  // config.stylix.targets.i3.exportedBarConfig
                )
              ];

              assigns = lib.mkOptionDefault {
                "1" = [ { class = "(?i)(?:firefox)"; } ];
                "2" = [ { class = "(?i)(?:geany)"; } ];
                "3" = [ { class = "(?i)(?:thunar)"; } ];
              };

              floating.criteria = [
                { class = "(?i)(?:qt5ct|pinentry)"; }
                { title = "(?i)(?:copying|deleting|moving)"; }
                { window_role = "(?i)(?:pop-up|setup)"; }
              ];

              window.commands = [
                {
                  criteria = {
                    urgent = "latest";
                  };
                  command = "focus";
                }
                {
                  criteria = {
                    class = "(?i)(?:qt5ct|pinentry)";
                  };
                  command = "floating enable, focus";
                }
                {
                  criteria = {
                    class = "^.*";
                  };
                  command = "border pixel 5";
                }
              ];
            };

            extraConfig = lib.mkAfter baseExtraConfig;
          };
        };
      };
    };
}
