{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      i3Enabled = lib.attrByPath [ "xsession" "windowManager" "i3" "enable" ] false config;
      commandDefaults = {
        launcher = "${lib.getExe pkgs.rofi} -modi drun -show drun";
        terminal = lib.getExe pkgs.kitty;
        browser = lib.getExe pkgs.firefox;
        emoji = "${lib.getExe pkgs.rofimoji} --selector rofi";
        playerctl = lib.getExe pkgs.playerctl;
        volume = lib.getExe pkgs.pamixer;
        brightness = lib.getExe pkgs.xorg.xbacklight;
        ocr = "${lib.getExe pkgs.normcap}";
        screenshot = "${lib.getExe pkgs.maim} -s -u | ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i";
      };
      commandOverrides = lib.attrByPath [ "gui" "i3" "commands" ] { } config;
      commands = commandDefaults // commandOverrides;
      mod = lib.attrByPath [ "xsession" "windowManager" "i3" "config" "modifier" ] "Mod4" config;
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
      rofiCommand = commands.launcher;
      kittyCommand = commands.terminal;
      firefoxCommand = commands.browser;
      rofimojiCommand = commands.emoji;
      playerctlCommand = commands.playerctl;
      pamixerCommand = commands.volume;
      xbacklightCommand = commands.brightness;
      screenshotCommand = commands.screenshot;
      ocrCommand = commands.ocr;
      logseqToggleCommand =
        commands.logseqToggle or "${config.xdg.configHome}/i3/scripts/toggle_logseq.sh";
      lockCommand = lib.attrByPath [ "gui" "i3" "lockCommand" ] (lib.getExe pkgs.i3lock-color) config;
    in
    {
      config = lib.mkIf i3Enabled {
        xsession.windowManager.i3 = {
          config = {
            keybindings = lib.mkOptionDefault (
              workspaceBindings
              // moveContainerBindings
              // {
                "Control+Shift+q" = "kill";
                "${mod}+Return" = "exec ${kittyCommand}";
                "${mod}+w" = "exec ${firefoxCommand}";
                "${mod}+d" = "exec ${rofiCommand}";
                "${mod}+b" = "exec ${rofimojiCommand}";
                "${mod}+Shift+c" = "reload";
                "${mod}+Shift+r" = "restart";
                "${mod}+Shift+q" = "kill";
                "${mod}+Shift+e" = "exec systemctl suspend";
                "${mod}+s" = "exec ${screenshotCommand}";
                "${mod}+Shift+o" = "exec --no-startup-id ${ocrCommand}";
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
                "Mod1+3" = "exec --no-startup-id ${logseqToggleCommand}";
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
          };

          extraConfig = lib.mkAfter gapsModesExtraConfig;
        };
      };
    };
}
