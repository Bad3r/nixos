{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      windowUtilsLib = pkgs.writeText "window_utils" ''
        #!/bin/sh

        # window_utils.sh: Calculate window position and size for i3 scratchpads

        SCREEN_SCALE=1.0
        TOPBAR_HEIGHT=29
        TOP_GAP=6
        BOTTOM_GAP=6
        OUTER_GAP=4

        get_primary_monitor_info() {
          xrandr --query | awk '/ connected primary/ {print $4}'
        }

        calculate() {
          echo "$1" | bc
        }

        calculate_int() {
          echo "$1" | bc | awk '{printf "%.0f\n", $1}'
        }

        calculate_window_geometry() {
          primary_monitor=$(get_primary_monitor_info)

          if [ -z "$primary_monitor" ]; then
            echo "Error: No primary monitor detected!" >&2
            exit 1
          fi

          screen_width=$(echo "$primary_monitor" | cut -d'x' -f1)
          screen_height=$(echo "$primary_monitor" | cut -d'x' -f2 | cut -d'+' -f1)
          screen_offset_x=$(echo "$primary_monitor" | awk -F '+' '{print $2}')
          screen_offset_y=$(echo "$primary_monitor" | awk -F '+' '{print $3}')

          if [ "$screen_width" -eq 3440 ] && [ "$screen_height" -eq 1440 ] && [ "$screen_offset_x" -eq 1440 ] && [ "$screen_offset_y" -eq 651 ]; then
            export TARGET_WIDTH=1134
            export TARGET_HEIGHT=1389
            export TARGET_X=2593
            export TARGET_Y=691
            return
          fi

          aspect_ratio=$(calculate "$screen_width / $screen_height")

          scaled_width=$(calculate_int "$screen_width * $SCREEN_SCALE")
          scaled_height=$(calculate_int "$screen_height * $SCREEN_SCALE")

          if [ "$(echo "$aspect_ratio >= 2.0" | bc)" -eq 1 ]; then
            target_width=$(calculate_int "$scaled_width / 3 - $OUTER_GAP")
          else
            target_width=$(calculate_int "$scaled_width / 2 - $OUTER_GAP")
          fi

          target_height=$(calculate_int "$scaled_height - $TOPBAR_HEIGHT - $TOP_GAP - $BOTTOM_GAP")
          target_x=$(calculate_int "$screen_offset_x + $scaled_width - $target_width")
          target_y=$(calculate_int "$screen_offset_y + $TOPBAR_HEIGHT + $TOP_GAP")

          export TARGET_WIDTH="$target_width"
          export TARGET_HEIGHT="$target_height"
          export TARGET_X="$target_x"
          export TARGET_Y="$target_y"
        }
      '';
      i3ScratchpadShowOrCreate = pkgs.writeShellApplication {
        name = "i3-scratchpad-show-or-create";
        runtimeInputs = [
          pkgs.i3
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          set -euo pipefail

          if [ "$#" -ne 2 ]; then
            echo "Usage: $0 <i3_mark> <launch_cmd>" >&2
            echo "Example: $0 'scratch-emacs' 'emacsclient -c -a emacs'" >&2
            exit 1
          fi

          I3_MARK="$1"
          LAUNCH_CMD="$2"

          scratchpad_exists() {
            i3-msg -t get_marks \
              | jq -e --arg mark "''${I3_MARK}" 'index($mark) != null' \
              >/dev/null
          }

          scratchpad_show() {
            if scratchpad_exists; then
              i3-msg "[con_mark=\"''${I3_MARK}\"] scratchpad show" >/dev/null
              return 0
            fi
            return 1
          }

          if scratchpad_show; then
            exit 0
          fi

          eval "''${LAUNCH_CMD}" &

          set +e
          WINDOW_ID="$(
            timeout 30 i3-msg -t subscribe '[ "window" ]' \
              | jq --unbuffered -r 'select(.change == "new") | .container.id' \
              | head -n1
          )"
          status=$?
          set -e

          if [ "''${status}" -ne 0 ] || [ -z "''${WINDOW_ID}" ]; then
            echo "Failed to detect new window for mark ''${I3_MARK}" >&2
            exit 1
          fi

          i3-msg "[con_id=''${WINDOW_ID}] mark \"''${I3_MARK}\", move scratchpad" >/dev/null
          scratchpad_show >/dev/null
        '';
      };

      toggleLogseqScript = pkgs.writeShellApplication {
        name = "toggle-logseq";
        runtimeInputs = [
          pkgs.bc
          pkgs.xorg.xrandr
          pkgs.procps
          pkgs.libnotify
          pkgs.i3
          pkgs.coreutils
          i3ScratchpadShowOrCreate
        ];
        text = ''
          set -euo pipefail

          : "''${USR_LIB_DIR:="''${HOME}/.local/lib"}"
          window_utils_lib="${windowUtilsLib}"

          if [ -f "''${USR_LIB_DIR}/window_utils" ]; then
            window_utils_lib="''${USR_LIB_DIR}/window_utils"
          fi

          # shellcheck source=/dev/null
          . "$window_utils_lib"

          calculate_window_geometry

          if ! pgrep -f logseq >/dev/null; then
            notify-send "Logseq" "Starting Logseq..."
            i3-scratchpad-show-or-create "Logseq" "logseq"
            sleep 5
          fi

          # shellcheck disable=SC2140
          i3-msg "[class=\"Logseq\"] scratchpad show, move position ''${TARGET_X}px ''${TARGET_Y}px, resize set ''${TARGET_WIDTH}px ''${TARGET_HEIGHT}px" >/dev/null
        '';
      };

      # Stylix colors (defined early for use in scripts)
      stylixColors = config.lib.stylix.colors.withHashtag or config.lib.stylix.colors;

      # Power profile switcher using rofi and system76-power
      powerProfileScript = pkgs.writeShellApplication {
        name = "power-profile-rofi";
        runtimeInputs = [
          pkgs.rofi
          pkgs.system76-power
          pkgs.libnotify
          pkgs.gnugrep
          pkgs.gawk
        ];
        text = ''
          set -euo pipefail

          # Get current profile
          current=$(system76-power profile 2>/dev/null | grep -oP '(?<=Power Profile: ).*' || echo "unknown")

          # Define profiles with icons
          battery="  Battery (power saving)"
          balanced="  Balanced (default)"
          performance="  Performance (max power)"

          # Mark current profile
          mark_current() {
            local profile="$1"
            local label="$2"
            if [ "$current" = "$profile" ]; then
              echo "$label ✓"
            else
              echo "$label"
            fi
          }

          # Build menu
          menu=$(printf "%s\n%s\n%s" \
            "$(mark_current "Battery" "$battery")" \
            "$(mark_current "Balanced" "$balanced")" \
            "$(mark_current "Performance" "$performance")")

          # Show rofi menu (Stylix-themed)
          chosen=$(echo "$menu" | rofi -dmenu -i -p "Power Profile" -theme-str '
            window { width: 320px; }
            listview { lines: 3; }
            element selected.normal { background-color: ${stylixColors.base02}; text-color: ${stylixColors.base05}; }
            element normal.active { text-color: ${stylixColors.base0B}; }
            element selected.active { background-color: ${stylixColors.base02}; text-color: ${stylixColors.base0B}; }
          ' || true)

          # Exit if nothing selected
          [ -z "$chosen" ] && exit 0

          # Extract profile name and apply
          case "$chosen" in
            *Battery*)
              system76-power profile battery
              notify-send -i battery "Power Profile" "Switched to Battery mode"
              ;;
            *Balanced*)
              system76-power profile balanced
              notify-send -i battery "Power Profile" "Switched to Balanced mode"
              ;;
            *Performance*)
              system76-power profile performance
              notify-send -i battery "Power Profile" "Switched to Performance mode"
              ;;
          esac
        '';
      };

      commandsDefault = {
        launcher = "${lib.getExe pkgs.rofi} -modi drun -show drun";
        terminal = lib.getExe pkgs.kitty;
        browser = lib.getExe pkgs.firefox;
        emoji = "${lib.getExe pkgs.rofimoji} --selector rofi";
        playerctl = lib.getExe pkgs.playerctl;
        volume = lib.getExe pkgs.pamixer;
        brightness = lib.getExe pkgs.xorg.xbacklight;
        screenshot = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
        logseqToggle = lib.getExe toggleLogseqScript;
        powerProfile = lib.getExe powerProfileScript;
      };
      # Use the already-defined stylixColors for consistency
      stylixColorsStrictWithHash = stylixColors;
      toLockColor =
        colorHex:
        let
          trimmed = lib.removePrefix "#" colorHex;
          normalized = if builtins.stringLength trimmed == 8 then trimmed else trimmed + "FF";
        in
        lib.strings.toUpper normalized;
      # Build lock palette directly from Stylix colors (no fallbacks)
      lockPalette = {
        background = toLockColor stylixColorsStrictWithHash.base00;
        ring = toLockColor stylixColorsStrictWithHash.base04;
        ringWrong = toLockColor stylixColorsStrictWithHash.base08;
        ringVerify = toLockColor stylixColorsStrictWithHash.base0B;
        line = toLockColor stylixColorsStrictWithHash.base03;
        text = toLockColor stylixColorsStrictWithHash.base05;
      };
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
        interval = 2;
        format = " $icon  $speed_down.eng(prefix:K)/s  $speed_up.eng(prefix:K)/s ";
        format_alt = " $icon {$ssid|$device} $ip ";
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
          output = [ "HDMI-0" ];
        }
        {
          workspace = "2";
          output = [ "HDMI-0" ];
        }
        {
          workspace = "3";
          output = [ "HDMI-0" ];
        }
        {
          workspace = "4";
          output = [ "HDMI-0" ];
        }
        {
          workspace = "5";
          output = [ "HDMI-0" ];
        }
        {
          workspace = "6";
          output = [ "HDMI-0" ];
        }
        {
          workspace = "7";
          output = [ "eDP-1-1" ];
        }
        {
          workspace = "8";
          output = [ "DP-1" ];
        }
        {
          workspace = "9";
          output = [ "DP-1" ];
        }
        {
          workspace = "10";
          output = [ "DP-1" ];
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
          i3ScratchpadShowOrCreate
          toggleLogseqScript
        ];

        home.file = {
          ".local/lib/window_utils" = {
            source = windowUtilsLib;
          };
        };

        programs.i3status-rust = {
          enable = true;
          bars.default = i3statusBarConfig;
        };

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

          "i3/scripts/toggle_logseq.sh" = {
            executable = true;
            source = "${toggleLogseqScript}/bin/toggle-logseq";
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

              startup = lib.mkAfter [
                {
                  command = "${lib.getExe' pkgs.hsetroot "hsetroot"} -solid '${stylixColorsStrictWithHash.base00}'";
                  always = true;
                  notification = false;
                }
                # DPMS: Keep screens on for 1 hour (3600s) before standby/suspend/off
                {
                  command = "${pkgs.xorg.xset}/bin/xset dpms 3600 3600 3600";
                  always = true;
                  notification = false;
                }
                # Screen saver: Blank after 1 hour (3600s)
                {
                  command = "${pkgs.xorg.xset}/bin/xset s 3600 3600";
                  always = true;
                  notification = false;
                }
              ];

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

              # Make split-direction hint use the same color as borders
              # (indicator equals border per state). Keep scope minimal and
              # avoid self-referencing config to prevent recursion.
              colors = {
                focused.indicator = lib.mkForce stylixColorsStrictWithHash.base0D;
                urgent.indicator = lib.mkForce stylixColorsStrictWithHash.base08;

                # Grouped per-state overrides to satisfy linters and avoid repetition
                focusedInactive = {
                  indicator = lib.mkForce stylixColorsStrictWithHash.base00;
                  border = lib.mkForce stylixColorsStrictWithHash.base00;
                  childBorder = lib.mkForce stylixColorsStrictWithHash.base00;
                };
                unfocused = {
                  indicator = lib.mkForce stylixColorsStrictWithHash.base03;
                  border = lib.mkForce stylixColorsStrictWithHash.base00;
                  childBorder = lib.mkForce stylixColorsStrictWithHash.base00;
                };
                placeholder = {
                  indicator = lib.mkForce stylixColorsStrictWithHash.base03;
                  border = lib.mkForce stylixColorsStrictWithHash.base00;
                  childBorder = lib.mkForce stylixColorsStrictWithHash.base00;
                };
              };

              workspaceAutoBackAndForth = true;
              inherit workspaceOutputAssign;

              gaps = {
                inner = 0;
                outer = 0;
                top = 0;
                bottom = 0;
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
                "1" = [ { class = "(?i)(?:geany)"; } ];
                "2" = [ { class = "(?i)(?:firefox)"; } ];
                "3" = [ { class = "(?i)(?:thunar)"; } ];
              };

              floating.criteria = [
                { class = "(?i)(?:qt5ct|pinentry)"; }
                { class = "claude-wpa"; }
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
                    class = "claude-wpa";
                  };
                  command = "floating enable, resize set 1270 695, move position center";
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
