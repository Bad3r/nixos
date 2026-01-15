{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Shell library for window geometry calculations (meant to be sourced, not executed)
      # Dependencies: xrandr (provided by sourcing script's runtimeInputs)
      windowUtilsLib = pkgs.writeText "window-utils-lib" /* bash */ ''
        # window_utils.sh: Calculate window position and size for i3 scratchpads
        # Exports: TARGET_WIDTH, TARGET_HEIGHT, TARGET_X, TARGET_Y

        # Layout constants
        TOPBAR_HEIGHT=29
        TOP_GAP=6
        BOTTOM_GAP=6
        OUTER_GAP=4

        calculate_window_geometry() {
          # Parse monitor info in single xrandr call using bash parameter expansion
          # Format: WIDTHxHEIGHT+OFFSET_X+OFFSET_Y (e.g., 2560x1440+0+0)
          local monitor_info
          monitor_info=$(xrandr --query | while read -r line; do
            [[ $line =~ \ connected\ primary\ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) ]] && \
              echo "''${BASH_REMATCH[1]} ''${BASH_REMATCH[2]} ''${BASH_REMATCH[3]} ''${BASH_REMATCH[4]}" && break
          done)

          if [[ -z $monitor_info ]]; then
            echo "Error: No primary monitor detected!" >&2
            return 1
          fi

          local screen_width screen_height screen_offset_x screen_offset_y
          read -r screen_width screen_height screen_offset_x screen_offset_y <<< "$monitor_info"

          # Determine width divisor: ultrawide (>=2:1) uses 1/3, standard uses 1/2
          # Integer comparison: width >= height*2 means aspect ratio >= 2.0
          local target_width
          if (( screen_width >= screen_height * 2 )); then
            target_width=$(( screen_width / 3 - OUTER_GAP ))
          else
            target_width=$(( screen_width / 2 - OUTER_GAP ))
          fi

          # All arithmetic done with bash builtins - no external processes
          export TARGET_WIDTH=$target_width
          export TARGET_HEIGHT=$(( screen_height - TOPBAR_HEIGHT - TOP_GAP - BOTTOM_GAP ))
          export TARGET_X=$(( screen_offset_x + screen_width - target_width ))
          export TARGET_Y=$(( screen_offset_y + TOPBAR_HEIGHT + TOP_GAP ))
        }
      '';
      i3ScratchpadShowOrCreate = pkgs.writeShellApplication {
        name = "i3-scratchpad-show-or-create";
        runtimeInputs = [
          pkgs.i3
          pkgs.coreutils
          pkgs.jq
        ];
        text = /* bash */ ''
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

      # Generic focus-or-launch script: focuses existing window or launches new instance
      focusOrLaunch = pkgs.writeShellApplication {
        name = "i3-focus-or-launch";
        runtimeInputs = [
          pkgs.i3
          pkgs.jq
        ];
        text = ''
          if [ "$#" -ne 2 ]; then
            echo "Usage: i3-focus-or-launch <class-pattern> <launch-command>" >&2
            exit 1
          fi

          CLASS_PATTERN="$1"
          LAUNCH_CMD="$2"

          # Check if any window with the class exists in i3 tree
          if i3-msg -t get_tree | jq -e --arg pattern "$CLASS_PATTERN" \
            '[.. | objects | select(.window_properties?.class? // "" | test($pattern; "i"))] | length > 0' \
            > /dev/null 2>&1; then
            i3-msg "[class=\"(?i)$CLASS_PATTERN\"] focus" > /dev/null
          else
            exec sh -c "$LAUNCH_CMD"
          fi
        '';
      };

      toggleLogseqScript = pkgs.writeShellApplication {
        name = "toggle-logseq";
        runtimeInputs = [
          pkgs.xorg.xrandr
          pkgs.procps
          pkgs.libnotify
          pkgs.i3
          pkgs.coreutils # for sleep
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
        launcher = "${lib.getExe pkgs.rofi} -config ~/.config/rofi/rofidmenu.rasi -modi drun -show drun";
        terminal = lib.getExe pkgs.kitty;
        browser = lib.getExe pkgs.firefox;
        emoji = "${lib.getExe pkgs.rofimoji} --selector rofi";
        playerctl = lib.getExe pkgs.playerctl;
        volume = lib.getExe pkgs.pamixer;
        brightness = lib.getExe pkgs.xorg.xbacklight;
        screenshot = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
        ocr = lib.getExe pkgs.normcap;
        logseqToggle = lib.getExe toggleLogseqScript;
        powerProfile = lib.getExe powerProfileScript;
        focusOrLaunch = lib.getExe focusOrLaunch;
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
      # Handle null defaults from options - use our defaults if option is null
      lockCommandValue =
        if config.gui.i3.lockCommand != null then config.gui.i3.lockCommand else lockCommandDefault;
      i3Commands = if config.gui.i3.commands != null then config.gui.i3.commands else commandsDefault;
      inherit (config.gui.i3) netInterface;
      netBlockBase = {
        block = "net";
        interval = 2;
        format = " $icon {$ssid|$device} $ip ";
        format_alt = "  $speed_down.eng(prefix:K)/s  $speed_up.eng(prefix:K)/s ";
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
        "title_align center"
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
          default = null;
          defaultText = lib.literalExpression "lib.getExe lockScript";
          example = "i3lock";
        };

        commands = lib.mkOption {
          description = "Commonly used command strings that other i3 modules can reuse.";
          type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
          default = null;
          defaultText = lib.literalExpression "commandsDefault";
          example = {
            launcher = "rofi -show drun";
            terminal = "kitty";
          };
        };

        browserClass = lib.mkOption {
          description = "Window class of the default browser for focus-or-launch and assigns.";
          type = lib.types.str;
          default = "firefox";
          example = "google-chrome";
        };
      };

      config = {
        # Expose resolved commands for other modules (e.g., i3-keybindings.nix)
        gui.i3.commands = lib.mkDefault commandsDefault;

        home.packages = [
          pkgs.rofimoji
          lockScript
          i3ScratchpadShowOrCreate
          focusOrLaunch
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
                "2" = [ { class = "(?i)(?:${config.gui.i3.browserClass})"; } ];
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
                    all = true;
                  };
                  command = ''border pixel 5, title_format "<b>%title</b>", title_window_icon padding 3px'';
                }
              ];
            };

            extraConfig = lib.mkAfter baseExtraConfig;
          };
        };
      };
    };
}
