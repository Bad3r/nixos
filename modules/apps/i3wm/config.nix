# i3 core configuration
# Defines options, scripts, startup commands, colors, and bar settings
# Window rules are in window-rules.nix
{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
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
          pkgs.procps
          pkgs.libnotify
          pkgs.i3
          pkgs.coreutils
          config.gui.scratchpad.geometryPackage
          pkgs.i3-scratchpad-show-or-create
        ];
        text = /* bash */ ''
          set -euo pipefail

          # Get window geometry from scratchpad-geometry calculator
          eval "$(scratchpad-geometry)"

          if ! pgrep -f logseq >/dev/null; then
            notify-send "Logseq" "Starting Logseq..."
            i3-scratchpad-show-or-create "Logseq" "logseq"
            sleep 5
          fi

          # shellcheck disable=SC2140
          i3-msg "[class=\"Logseq\"] scratchpad show, move position ''${TARGET_X}px ''${TARGET_Y}px, resize set ''${TARGET_WIDTH}px ''${TARGET_HEIGHT}px" >/dev/null
        '';
      };

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
        browser = lib.getExe config.programs.floorp.finalPackage;
        emoji = "${lib.getExe pkgs.rofimoji} --selector rofi";
        playerctl = lib.getExe pkgs.playerctl;
        volume = lib.getExe pkgs.pamixer;
        brightness = lib.getExe pkgs.xbacklight;
        screenshot = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
        ocr = lib.getExe pkgs.normcap;
        logseqToggle = lib.getExe toggleLogseqScript;
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
          default = "floorp";
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
