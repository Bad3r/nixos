# i3 core configuration
# Defines options, scripts, startup commands, colors, and bar settings
# Window rules are in window-rules.nix
{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      osConfig ? { },
      pkgs,
      lib,
      ...
    }:
    let
      hostI3Cfg = lib.attrByPath [ "gui" "i3" ] { } osConfig;
      powerProfileBackend = lib.attrByPath [ "powerProfiles" "backend" ] "powerprofilesctl" hostI3Cfg;
      powerProfileSelectionAllowed = lib.attrByPath [ "powerProfiles" "allowSelection" ] true hostI3Cfg;
      sessionMetadata = {
        DESKTOP_SESSION = "none+i3";
        # `i3` is included as a standalone token so xdg-desktop-portal picks up
        # the i3-scoped portals.conf (split is `:`, not `+`).
        XDG_CURRENT_DESKTOP = "none+i3:i3:X-NIXOS-SYSTEMD-AWARE";
        XDG_SESSION_TYPE = "x11";
      };
      sessionMetadataExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") sessionMetadata
      );
      graphicalEnvVars = [
        "DBUS_SESSION_BUS_ADDRESS"
        "DESKTOP_SESSION"
        "DISPLAY"
        "PATH"
        "QML2_IMPORT_PATH"
        "QT_PLUGIN_PATH"
        "QT_QPA_PLATFORMTHEME"
        "QT_STYLE_OVERRIDE"
        "SSH_AUTH_SOCK"
        "XAUTHORITY"
        "XDG_CONFIG_DIRS"
        "XDG_CURRENT_DESKTOP"
        "XDG_DATA_DIRS"
        "XDG_RUNTIME_DIR"
        "XDG_SESSION_ID"
        "XDG_SESSION_TYPE"
      ];
      graphicalEnvArgs = lib.concatStringsSep " " graphicalEnvVars;

      # Stylix colors (defined early for use in scripts)
      stylixColors = config.lib.stylix.colors.withHashtag or config.lib.stylix.colors;

      # Toggle Logseq scratchpad - uses config.gui.scratchpad.geometryPackage
      toggleLogseqScript = pkgs.writeShellApplication {
        name = "toggle-logseq";
        meta = {
          description = "Toggle Logseq as an i3 scratchpad with smart positioning";
          license = lib.licenses.mit;
          platforms = lib.platforms.linux;
          mainProgram = "toggle-logseq";
        };
        runtimeInputs = [
          pkgs.libnotify
          pkgs.i3
          pkgs.coreutils
          pkgs.jq
          config.gui.scratchpad.geometryPackage
        ];
        text = /* bash */ ''
          set -euo pipefail

          # Get window geometry from scratchpad-geometry calculator
          eval "$(scratchpad-geometry)"

          logseq_mark="Logseq"
          logseq_class_pattern="^logseq$"
          logseq_criteria='[class="(?i)^logseq$"]'

          logseq_window_exists() {
            i3-msg -t get_tree \
              | jq -e --arg pattern "''${logseq_class_pattern}" \
                '.. | objects | select((.window_properties?.class? // "") | test($pattern; "i"))' \
              >/dev/null
          }

          scratchpad_marked() {
            i3-msg -t get_marks \
              | jq -e --arg mark "''${logseq_mark}" 'index($mark) != null' \
              >/dev/null
          }

          if ! logseq_window_exists; then
            notify-send "Logseq" "Starting Logseq..."
            logseq &

            for _ in $(seq 1 150); do
              if logseq_window_exists; then
                break
              fi
              sleep 0.2
            done
          fi

          if ! logseq_window_exists; then
            echo "Failed to detect Logseq window" >&2
            exit 1
          fi

          if ! scratchpad_marked; then
            i3-msg "''${logseq_criteria} mark \"''${logseq_mark}\", move scratchpad" >/dev/null
          fi

          i3-msg "[con_mark=\"''${logseq_mark}\"] scratchpad show, move position ''${TARGET_X}px ''${TARGET_Y}px, resize set ''${TARGET_WIDTH}px ''${TARGET_HEIGHT}px" >/dev/null
        '';
      };

      # Toggle Raindrop scratchpad
      toggleRaindropScript = pkgs.writeShellApplication {
        name = "toggle-raindrop";
        meta = {
          description = "Toggle Raindrop as an i3 scratchpad with smart positioning";
          license = lib.licenses.mit;
          platforms = lib.platforms.linux;
          mainProgram = "toggle-raindrop";
        };
        runtimeInputs = [
          pkgs.libnotify
          pkgs.i3
          pkgs.coreutils
          pkgs.jq
          config.gui.scratchpad.geometryPackage
        ]
        ++ lib.optional (pkgs ? raindrop) pkgs.raindrop;
        text = /* bash */ ''
          set -euo pipefail

          eval "$(scratchpad-geometry)"

          raindrop_mark="Raindrop"
          raindrop_class_pattern="^raindrop$"
          raindrop_criteria='[class="(?i)^raindrop$"]'

          raindrop_window_exists() {
            i3-msg -t get_tree \
              | jq -e --arg pattern "''${raindrop_class_pattern}" \
                '.. | objects | select((.window_properties?.class? // "") | test($pattern; "i"))' \
              >/dev/null
          }

          scratchpad_marked() {
            i3-msg -t get_marks \
              | jq -e --arg mark "''${raindrop_mark}" 'index($mark) != null' \
              >/dev/null
          }

          if ! raindrop_window_exists; then
            notify-send "Raindrop" "Starting Raindrop..."
            raindrop &

            for _ in $(seq 1 150); do
              if raindrop_window_exists; then
                break
              fi
              sleep 0.2
            done
          fi

          if ! raindrop_window_exists; then
            echo "Failed to detect Raindrop window" >&2
            exit 1
          fi

          if ! scratchpad_marked; then
            i3-msg "''${raindrop_criteria} mark \"''${raindrop_mark}\", move scratchpad" >/dev/null
          fi

          i3-msg "[con_mark=\"''${raindrop_mark}\"] scratchpad show, move position ''${TARGET_X}px ''${TARGET_Y}px, resize set ''${TARGET_WIDTH}px ''${TARGET_HEIGHT}px" >/dev/null
        '';
      };

      # Power profile switcher using the host-selected backend
      powerProfileScript = pkgs.writeShellApplication {
        name = "power-profile-rofi";
        runtimeInputs = [
          pkgs.libnotify
          pkgs.rofi
        ]
        ++ lib.optionals (powerProfileBackend == "system76-power") [
          pkgs.gawk
          pkgs.gnugrep
          pkgs.system76-power
        ]
        ++ lib.optionals (powerProfileBackend == "powerprofilesctl") [
          pkgs.power-profiles-daemon
        ];
        text = ''
          set -euo pipefail
          backend=${lib.escapeShellArg powerProfileBackend}
          selection_allowed=${lib.escapeShellArg (if powerProfileSelectionAllowed then "true" else "false")}

          # Get current profile
          if [ "$backend" = "powerprofilesctl" ]; then
            current=$(powerprofilesctl get 2>/dev/null || echo "unknown")
          else
            current=$(system76-power profile 2>/dev/null | grep -oP '(?<=Power Profile: ).*' || echo "unknown")
          fi

          if [ "$selection_allowed" != "true" ]; then
            if [ "$backend" = "powerprofilesctl" ]; then
              powerprofilesctl set performance
            else
              system76-power profile performance
            fi
            notify-send -i battery "Power Profile" "Performance mode is enforced on this host"
            exit 0
          fi

          if [ "$backend" = "powerprofilesctl" ]; then
            power_saver_profile="power-saver"
            power_saver_label="  Power Saver"
            balanced_profile="balanced"
            balanced_label="  Balanced"
            performance_profile="performance"
            performance_label="  Performance"
          else
            power_saver_profile="Battery"
            power_saver_label="  Battery (power saving)"
            balanced_profile="Balanced"
            balanced_label="  Balanced (default)"
            performance_profile="Performance"
            performance_label="  Performance (max power)"
          fi

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
            "$(mark_current "$power_saver_profile" "$power_saver_label")" \
            "$(mark_current "$balanced_profile" "$balanced_label")" \
            "$(mark_current "$performance_profile" "$performance_label")")

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
            *Power\ Saver*|*Battery*)
              if [ "$backend" = "powerprofilesctl" ]; then
                powerprofilesctl set power-saver
              else
                system76-power profile battery
              fi
              notify-send -i battery "Power Profile" "Switched to Power Saver mode"
              ;;
            *Balanced*)
              if [ "$backend" = "powerprofilesctl" ]; then
                powerprofilesctl set balanced
              else
                system76-power profile balanced
              fi
              notify-send -i battery "Power Profile" "Switched to Balanced mode"
              ;;
            *Performance*)
              if [ "$backend" = "powerprofilesctl" ]; then
                powerprofilesctl set performance
              else
                system76-power profile performance
              fi
              notify-send -i battery "Power Profile" "Switched to Performance mode"
              ;;
          esac
        '';
      };

      commandsDefault = {
        launcher = "${lib.getExe pkgs.rofi} -config ~/.config/rofi/rofidmenu.rasi -modi drun -show drun";
        terminal = lib.getExe pkgs.kitty;
        browser = lib.getExe config.programs.librewolf.finalPackage;
        emoji = "${lib.getExe pkgs.rofimoji} --selector rofi";
        bluetoothMenu = "${lib.getExe pkgs.bzmenu} --launcher rofi";
        playerctl = lib.getExe pkgs.playerctl;
        volume = lib.getExe pkgs.pamixer;
        brightness = lib.getExe pkgs.xbacklight;
        screenshot = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
        ocr = lib.getExe pkgs.normcap;
        logseqToggle = lib.getExe toggleLogseqScript;
        raindropToggle = lib.getExe toggleRaindropScript;
        powerProfile = lib.getExe powerProfileScript;
        focusOrLaunch = lib.getExe pkgs.i3-focus-or-launch;
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
          pkgs.xbacklight
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
          default = "librewolf";
          example = "firefox";
        };

        borderWidth = lib.mkOption {
          description = "Window border width in pixels for positioning calculations.";
          type = lib.types.int;
          default = 5;
          example = 3;
        };

        screenWidth = lib.mkOption {
          description = "Primary screen width in pixels for window positioning calculations.";
          type = lib.types.int;
          default = 2560;
          example = 1920;
        };

        screenHeight = lib.mkOption {
          description = "Primary screen height in pixels for window positioning calculations.";
          type = lib.types.int;
          default = 1440;
          example = 1080;
        };

        fontSize = lib.mkOption {
          description = "Desktop font size in pixels. Defaults to Stylix desktop font size.";
          type = lib.types.int;
          default = config.stylix.fonts.sizes.desktop;
          defaultText = lib.literalExpression "config.stylix.fonts.sizes.desktop";
          example = 12;
        };

        barHeight = lib.mkOption {
          description = "Status bar height in pixels. Derived from fontSize plus border padding.";
          type = lib.types.int;
          default = (config.gui.i3.fontSize * 2) + (config.gui.i3.borderWidth * 2);
          defaultText = lib.literalExpression "(fontSize * 2) + (borderWidth * 2)";
          example = 34;
        };
      };

      config = {
        # Expose resolved commands for other modules (e.g., keybindings.nix)
        gui.i3.commands = lib.mkDefault commandsDefault;

        home.packages = [
          pkgs.rofimoji
          lockScript
          pkgs.i3-scratchpad-show-or-create
          pkgs.i3-focus-or-launch
          toggleLogseqScript
          toggleRaindropScript
        ];

        xdg.configFile = {
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

          "i3/scripts/toggle_raindrop.sh" = {
            executable = true;
            source = "${toggleRaindropScript}/bin/toggle-raindrop";
          };
        };

        xsession = {
          enable = true;
          importedVariables = lib.mkAfter graphicalEnvVars;
          profileExtra = lib.mkAfter ''
            ${sessionMetadataExports}
            ${lib.getExe' pkgs.dbus "dbus-update-activation-environment"} --systemd ${graphicalEnvArgs}
          '';
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
            };

            extraConfig = lib.mkAfter baseExtraConfig;
          };
        };
      };
    };
}
