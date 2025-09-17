{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      netInterface = lib.attrByPath [ "gui" "i3" "netInterface" ] null config;
      stylixBarOverrides = lib.attrByPath [ "lib" "stylix" "i3status-rust" "bar" ] null config;
      themeSettings = {
        theme = "plain";
      }
      // lib.optionalAttrs (stylixBarOverrides != null) {
        overrides = stylixBarOverrides;
      };
      mod = config.xsession.windowManager.i3.config.modifier;
      stylixAvailable = config ? stylix && config.stylix ? targets && config.stylix.targets ? i3;
      stylixExportedBarConfig =
        if stylixAvailable then config.stylix.targets.i3.exportedBarConfig else { };
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
      stylixFontName =
        if stylixAvailable && config.stylix.fonts ? sansSerif then
          config.stylix.fonts.sansSerif.name
        else
          null;
      stylixFontSize =
        if stylixAvailable && config.stylix.fonts ? sizes then config.stylix.fonts.sizes.desktop else null;
      stylixBarOptions =
        (lib.optionalAttrs (stylixExportedBarConfig ? colors) {
          inherit (stylixExportedBarConfig) colors;
        })
        // (lib.optionalAttrs (stylixFontName != null && stylixFontSize != null) {
          fonts = {
            names = [ stylixFontName ];
            size = stylixFontSize * 1.0;
          };
        });

      rofiCommand = "${lib.getExe pkgs.rofi} -modi drun -show drun";
      kittyCommand = lib.getExe pkgs.kitty;
      firefoxCommand = lib.getExe pkgs.firefox;
      rofimojiCommand = "${lib.getExe pkgs.rofimoji} --selector rofi";
      playerctlCommand = lib.getExe pkgs.playerctl;
      pamixerCommand = lib.getExe pkgs.pamixer;
      xbacklightCommand = lib.getExe pkgs.xorg.xbacklight;
      screenshotCommand = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
      lockScript = pkgs.writeShellApplication {
        name = "i3lock-stylix";
        runtimeInputs = [ pkgs.i3lock-color ];
        text = ''
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
      lockCommand = lib.getExe lockScript;

      workspaceNumbers = map toString (lib.range 1 10);
      toWorkspaceKey = ws: if ws == "10" then "0" else ws;
      workspaceBindings = lib.listToAttrs (
        map (ws: lib.nameValuePair "${mod}+${toWorkspaceKey ws}" "workspace number ${ws}") workspaceNumbers
      );
      moveContainerBindings = lib.listToAttrs (
        map (
          ws: lib.nameValuePair "${mod}+Shift+${toWorkspaceKey ws}" "move container to workspace number ${ws}"
        ) workspaceNumbers
      );

      resizeModeBindings = {
        h = "resize shrink width 10 px or 10 ppt";
        j = "resize grow height 10 px or 10 ppt";
        k = "resize shrink height 10 px or 10 ppt";
        l = "resize grow width 10 px or 10 ppt";
        Left = "resize shrink width 10 px or 10 ppt";
        Down = "resize grow height 10 px or 10 ppt";
        Up = "resize shrink height 10 px or 10 ppt";
        Right = "resize grow width 10 px or 10 ppt";
        Return = "mode default";
        Escape = "mode default";
        "${mod}+r" = "mode default";
      };

      gapsModeName = "Gaps: (o) outer, (i) inner, (h) horizontal, (v) vertical, (t) top, (r) right, (b) bottom, (l) left";
      gapsModeOuter = "Outer Gaps: +|-|0 (local), Shift + +|-|0 (global)";
      gapsModeInner = "Inner Gaps: +|-|0 (local), Shift + +|-|0 (global)";
      gapsModeHoriz = "Horizontal Gaps: +|-|0 (local), Shift + +|-|0 (global)";
      gapsModeVert = "Vertical Gaps: +|-|0 (local), Shift + +|-|0 (global)";
      gapsModeTop = "Top Gaps: +|-|0 (local), Shift + +|-|0 (global)";
      gapsModeRight = "Right Gaps: +|-|0 (local), Shift + +|-|0 (global)";
      gapsModeBottom = "Bottom Gaps: +|-|0 (local), Shift + +|-|0 (global)";
      gapsModeLeft = "Left Gaps: +|-|0 (local), Shift + +|-|0 (global)";

      gapsModesExtraConfig = ''
        mode "${gapsModeName}" {
          bindsym o mode "${gapsModeOuter}"
          bindsym i mode "${gapsModeInner}"
          bindsym h mode "${gapsModeHoriz}"
          bindsym v mode "${gapsModeVert}"
          bindsym t mode "${gapsModeTop}"
          bindsym r mode "${gapsModeRight}"
          bindsym b mode "${gapsModeBottom}"
          bindsym l mode "${gapsModeLeft}"
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeOuter}" {
          bindsym plus gaps outer current plus 5
          bindsym minus gaps outer current minus 5
          bindsym 0 gaps outer current set 0
          bindsym Shift+plus gaps outer all plus 5
          bindsym Shift+minus gaps outer all minus 5
          bindsym Shift+0 gaps outer all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeInner}" {
          bindsym plus gaps inner current plus 5
          bindsym minus gaps inner current minus 5
          bindsym 0 gaps inner current set 0
          bindsym Shift+plus gaps inner all plus 5
          bindsym Shift+minus gaps inner all minus 5
          bindsym Shift+0 gaps inner all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeHoriz}" {
          bindsym plus gaps horizontal current plus 5
          bindsym minus gaps horizontal current minus 5
          bindsym 0 gaps horizontal current set 0
          bindsym Shift+plus gaps horizontal all plus 5
          bindsym Shift+minus gaps horizontal all minus 5
          bindsym Shift+0 gaps horizontal all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeVert}" {
          bindsym plus gaps vertical current plus 5
          bindsym minus gaps vertical current minus 5
          bindsym 0 gaps vertical current set 0
          bindsym Shift+plus gaps vertical all plus 5
          bindsym Shift+minus gaps vertical all minus 5
          bindsym Shift+0 gaps vertical all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeTop}" {
          bindsym plus gaps top current plus 5
          bindsym minus gaps top current minus 5
          bindsym 0 gaps top current set 0
          bindsym Shift+plus gaps top all plus 5
          bindsym Shift+minus gaps top all minus 5
          bindsym Shift+0 gaps top all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeRight}" {
          bindsym plus gaps right current plus 5
          bindsym minus gaps right current minus 5
          bindsym 0 gaps right current set 0
          bindsym Shift+plus gaps right all plus 5
          bindsym Shift+minus gaps right all minus 5
          bindsym Shift+0 gaps right all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeBottom}" {
          bindsym plus gaps bottom current plus 5
          bindsym minus gaps bottom current minus 5
          bindsym 0 gaps bottom current set 0
          bindsym Shift+plus gaps bottom all plus 5
          bindsym Shift+minus gaps bottom all minus 5
          bindsym Shift+0 gaps bottom all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }

        mode "${gapsModeLeft}" {
          bindsym plus gaps left current plus 5
          bindsym minus gaps left current minus 5
          bindsym 0 gaps left current set 0
          bindsym Shift+plus gaps left all plus 5
          bindsym Shift+minus gaps left all minus 5
          bindsym Shift+0 gaps left all set 0
          bindsym Return mode "${gapsModeName}"
          bindsym Escape mode "default"
        }
      '';

      extraConfigLines = [
        "default_orientation horizontal"
        "popup_during_fullscreen smart"
        "new_window normal"
        "new_float normal"
        ""
        gapsModesExtraConfig
      ];

      extraConfig = lib.concatStringsSep "\n" extraConfigLines;

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

      netBlock = {
        block = "net";
        interval = 5;
      }
      // lib.optionalAttrs (netInterface != null) { device = netInterface; };
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
        }
        {
          block = "memory";
          format = " $icon $mem_total_used_percents ";
          format_alt = " $icon_swap $swap_used_percents ";
        }
        {
          block = "cpu";
          interval = 1;
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
        { block = "sound"; }
        {
          block = "battery";
          interval = 30;
          format = " $icon $percentage ";
        }
        {
          block = "time";
          interval = 60;
          format = " $timestamp.datetime(f:'%a %d/%m %R') ";
        }
      ];
      i3statusBarConfig = {
        icons = "awesome6";
        blocks = i3statusBlocks;
        settings = {
          icons_format = "{icon}";
          icons.overrides = {
            cpu = "";
            update = "";
          };
          theme = themeSettings;
        };
      };
    in
    {
      options.gui.i3.netInterface = lib.mkOption {
        description = "Primary network interface for the i3status net block.";
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "enp4s0";
      };

      options.gui.i3.lockCommand = lib.mkOption {
        description = "Command used to lock the screen within the i3 session.";
        type = lib.types.nullOr lib.types.str;
        default = lockCommand;
        example = "i3lock";
      };

      config = lib.mkMerge [
        {
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
                exec ${lockCommand} "$@"
              '';
            };

            "i3/scripts/blur-lock" = {
              executable = true;
              text = ''
                #!/usr/bin/env bash
                exec ${lockCommand} "$@"
              '';
            };
          };

          xsession = {
            enable = true;
            windowManager.i3 = {
              enable = true;
              config = {
                modifier = lib.mkDefault "Mod4";
                terminal = kittyCommand;
                menu = rofiCommand;

                floating = {
                  modifier = "Mod1";
                  border = 5;
                };

                focus = {
                  followMouse = true;
                  newWindow = "focus";
                };

                window = {
                  border = 5;
                  hideEdgeBorders = "both";
                };

                workspaceAutoBackAndForth = true;
                inherit workspaceOutputAssign;

                gaps = {
                  inner = 2;
                  outer = 2;
                  top = 2;
                  bottom = 2;
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
                    // stylixBarOptions
                  )
                ];

                assigns = lib.mkOptionDefault {
                  "1" = [ { class = "(?i)(?:firefox)"; } ];
                  "2" = [ { class = "(?i)(?:geany)"; } ];
                  "3" = [ { class = "(?i)(?:thunar)"; } ];
                };

                keybindings = lib.mkOptionDefault (
                  workspaceBindings
                  // moveContainerBindings
                  // {
                    "Control+Shift+q" = "kill";
                    "${mod}+Return" = "exec ${kittyCommand}";
                    "Control+Shift+t" = "exec ${kittyCommand}";
                    "${mod}+w" = "exec ${firefoxCommand}";
                    "${mod}+d" = "exec ${rofiCommand}";
                    "${mod}+b" = "exec ${rofimojiCommand}";
                    "${mod}+Shift+c" = "reload";
                    "${mod}+Shift+r" = "restart";
                    "${mod}+Shift+q" = "kill";
                    "${mod}+Shift+e" = "exec systemctl suspend";
                    "${mod}+s" = "exec ${screenshotCommand}";
                    "${mod}+f" = "fullscreen toggle";
                    "${mod}+semicolon" = "split horizontal";
                    "${mod}+v" = "split vertical";
                    "${mod}+t" = "split toggle";
                    "${mod}+Shift+s" = "layout stacking";
                    "${mod}+Shift+t" = "layout tabbed";
                    "${mod}+Shift+x" = "layout toggle split";
                    "${mod}+space" = "floating toggle";
                    "${mod}+Shift+space" = "focus mode_toggle";
                    "${mod}+p" = "focus parent";
                    "${mod}+c" = "focus child";
                    "${mod}+Shift+z" = "move scratchpad";
                    "${mod}+z" = "scratchpad show";
                    "${mod}+Shift+b" = "border toggle";
                    "${mod}+n" = "border normal";
                    "${mod}+y" = "border pixel 3";
                    "${mod}+u" = "border none";
                    "Mod1+1" = "workspace prev";
                    "Mod1+2" = "workspace next";
                    "${mod}+h" = "focus left";
                    "${mod}+j" = "focus down";
                    "${mod}+k" = "focus up";
                    "${mod}+l" = "focus right";
                    "${mod}+Shift+h" = "move left";
                    "${mod}+Shift+j" = "move down";
                    "${mod}+Shift+k" = "move up";
                    "${mod}+Shift+l" = "move right";
                    "XF86AudioPlay" = "exec ${playerctlCommand} play-pause";
                    "XF86AudioNext" = "exec ${playerctlCommand} next";
                    "XF86AudioPrev" = "exec ${playerctlCommand} previous";
                    "XF86AudioStop" = "exec ${playerctlCommand} stop";
                    "XF86AudioMute" = "exec ${pamixerCommand} -t";
                    "XF86AudioRaiseVolume" = "exec ${pamixerCommand} -i 2";
                    "XF86AudioLowerVolume" = "exec ${pamixerCommand} -d 2";
                    "XF86MonBrightnessUp" = "exec ${xbacklightCommand} -inc 10";
                    "XF86MonBrightnessDown" = "exec ${xbacklightCommand} -dec 10";
                    "${mod}+Shift+g" = "mode \"${gapsModeName}\"";
                    "${mod}+Control+l" = "exec ${lockCommand}";
                  }
                );

                keycodebindings = {
                  "Mod1+23" = "layout toggle tabbed split";
                  "${mod}+23" = "layout toggle splitv splith";
                };

                modes = lib.mkOptionDefault { resize = resizeModeBindings; };

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
                ];
              };

              extraConfig = lib.mkAfter extraConfig;
            };
          };
        }
      ];
    };
}
