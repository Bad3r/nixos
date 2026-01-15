# i3 keybindings configuration
{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Get modifier from i3 config
      mod = lib.attrByPath [ "xsession" "windowManager" "i3" "config" "modifier" ] "Mod4" config;

      # Get commands from gui.i3.commands (defaults set in i3-config.nix)
      inherit (config.gui.i3) commands;

      # Lock command
      lockCommand =
        if config.gui.i3.lockCommand != null then
          config.gui.i3.lockCommand
        else
          lib.getExe pkgs.i3lock-color;

      # Workspace bindings (1-10, using 0 for workspace 10)
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

      # Resize mode
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

      # Gaps mode
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
    in
    {
      config = {
        xsession.windowManager.i3.config = {
          keybindings = lib.mkOptionDefault (
            workspaceBindings
            // moveContainerBindings
            // {
              # Window management
              "Control+Shift+q" = "kill";
              "${mod}+Shift+q" = "kill";
              "${mod}+f" = "fullscreen toggle";

              # Launchers
              "${mod}+Return" = "exec ${commands.terminal}";
              "${mod}+w" =
                "exec --no-startup-id ${commands.focusOrLaunch} '${config.gui.i3.browserClass}' '${commands.browser}'";
              "${mod}+d" = "exec ${commands.launcher}";
              "${mod}+b" = "exec ${commands.emoji}";
              "${mod}+s" = "exec ${commands.screenshot}";
              "${mod}+Shift+o" = "exec --no-startup-id ${commands.ocr}";

              # i3 control
              "${mod}+Shift+c" = "reload";
              "${mod}+Shift+r" = "restart";
              "${mod}+Shift+e" = "exec systemctl suspend";
              "${mod}+Control+l" = "exec ${lockCommand}";
              "${mod}+Shift+p" = "exec --no-startup-id ${commands.powerProfile}";

              # Layout
              "${mod}+semicolon" = "split horizontal";
              "${mod}+v" = "split vertical";
              "${mod}+t" = "split toggle";
              "${mod}+Shift+s" = "layout stacking";
              "${mod}+Shift+t" = "layout tabbed";
              "${mod}+Shift+x" = "layout toggle split";

              # Floating
              "${mod}+space" = "floating toggle";
              "${mod}+Shift+space" = "focus mode_toggle";

              # Focus
              "${mod}+p" = "focus parent";
              "${mod}+c" = "focus child";
              "${mod}+h" = "focus left";
              "${mod}+j" = "focus down";
              "${mod}+k" = "focus up";
              "${mod}+l" = "focus right";

              # Move windows
              "${mod}+Shift+h" = "move left";
              "${mod}+Shift+j" = "move down";
              "${mod}+Shift+k" = "move up";
              "${mod}+Shift+l" = "move right";

              # Scratchpad
              "${mod}+Shift+z" = "move scratchpad";
              "${mod}+z" = "scratchpad show";

              # Borders
              "${mod}+Shift+b" = "border toggle";
              "${mod}+n" = "border normal";
              "${mod}+y" = "border pixel 3";
              "${mod}+u" = "border none";

              # Workspace navigation (Alt+1/2 for prev/next)
              "Mod1+1" = "workspace prev";
              "Mod1+2" = "workspace next";

              # Scratchpad apps
              "Mod1+3" = "exec --no-startup-id ${commands.logseqToggle}";
              "${mod}+e" =
                "exec --no-startup-id i3-scratchpad-show-or-create scratch-nvim '${commands.terminal} nvim'";

              # Media keys
              "XF86AudioPlay" = "exec ${commands.playerctl} play-pause";
              "XF86AudioNext" = "exec ${commands.playerctl} next";
              "XF86AudioPrev" = "exec ${commands.playerctl} previous";
              "XF86AudioStop" = "exec ${commands.playerctl} stop";
              "XF86AudioMute" = "exec ${commands.volume} -t";
              "XF86AudioRaiseVolume" = "exec ${commands.volume} -i 2";
              "XF86AudioLowerVolume" = "exec ${commands.volume} -d 2";
              "XF86MonBrightnessUp" = "exec ${commands.brightness} -inc 10";
              "XF86MonBrightnessDown" = "exec ${commands.brightness} -dec 10";

              # Modes
              "${mod}+Shift+g" = "mode \"${gapsModeName}\"";
              "${mod}+r" = "mode resize";
            }
          );

          keycodebindings = {
            "Mod1+23" = "layout toggle tabbed split"; # Alt+Tab
            "${mod}+23" = "layout toggle splitv splith"; # Mod+Tab
          };

          modes = lib.mkOptionDefault { resize = resizeModeBindings; };
        };

        xsession.windowManager.i3.extraConfig = lib.mkAfter gapsModesExtraConfig;
      };
    };
}
