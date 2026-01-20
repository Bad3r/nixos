/*
  Package: rofi
  Description: Window switcher, application launcher, and dmenu replacement with plugin system.
  Homepage: https://github.com/davatorium/rofi
  Documentation: https://github.com/davatorium/rofi/blob/next/doc/rofi.1.md
  Repository: https://github.com/davatorium/rofi

  Summary:
    * Provides a customizable launcher supporting modes for running applications, switching windows, SSH, scripts, file browsers, and more.
    * Features themes, keybinding customization, history, and scriptable "modi" to extend functionality beyond launching apps.
    * Theme colors automatically synced with Stylix configuration.

  Features:
    * Colors automatically managed by stylix.targets.rofi (base16 scheme)
    * Multiple specialized themes: dmenu (apps), powermenu, power-profiles, keyhint
    * Modes: window, drun, run, ssh, combi, filebrowser, calc
    * Calculator mode via rofi-calc plugin (uses libqalculate for natural language math)
    * Terminal integration for running console applications

  Config files installed:
    * ~/.config/rofi/rofidmenu.rasi      - Apps menu layout (single column, 6 lines)
    * ~/.config/rofi/powermenu.rasi      - Power menu layout (east sidebar, 7 lines)
    * ~/.config/rofi/power-profiles.rasi - Power profile selector (east, 4 lines)
    * ~/.config/rofi/rofikeyhint.rasi    - Keybinding hints (1 column, 10 lines)

  Example Usage:
    * `rofi -show drun` — Default app launcher with stylix colors.
    * `rofi -config ~/.config/rofi/rofidmenu.rasi -show drun` — Apps in compact single-column list.
    * `rofi -show calc -modi calc -no-show-match -no-sort` — Calculator with natural language.
    * `echo -e "Shutdown\nRestart" | rofi -dmenu -config ~/.config/rofi/powermenu.rasi` — Power menu.
    * `rofi -config ~/.config/rofi/rofikeyhint.rasi -show keys` — Show keybindings.
*/

_: {
  flake.homeManagerModules.apps.rofi =
    {
      osConfig,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "rofi" "extended" "enable" ] false osConfig;

      # Get terminal from i3 commands if available, fallback to kitty
      terminal =
        let
          i3Commands = lib.attrByPath [ "gui" "i3" "commands" ] { } config;
        in
        i3Commands.terminal or "${lib.getExe pkgs.kitty}";

      # Layout-only styles (colors handled by stylix via programs.rofi.theme)
      commonLayoutStyles = ''
        element {
            border:  0;
            padding: 1px;
        }
        scrollbar {
            width:        4px;
            border:       0;
            handle-width: 8px;
            padding:      0;
        }
        mode-switcher {
            border: 2px 0px 0px;
        }
        button {
            spacing: 0;
        }
        inputbar {
            spacing:  0;
            padding:  1px;
            children: [ prompt,textbox-prompt-colon,entry,case-indicator ];
        }
        case-indicator {
            spacing: 0;
        }
        entry {
            spacing: 0;
        }
        prompt {
            spacing: 0;
        }
        textbox-prompt-colon {
            expand: false;
            str:    ":";
            margin: 0px 0.3em 0em 0em;
        }
      '';

      # Apps menu config (rofidmenu.rasi)
      # Imports main config.rasi for stylix colors, then overrides layout
      rofidmenuConfig = ''
        /* Apps menu - compact single column, 6 lines */
        @import "config"

        window {
            background-color: @background;
            border:           5;
            border-color:     @border-color;
            padding:          5;
            transparency:     "none";
        }
        listview {
            lines:        6;
            fixed-height: 0;
            border:       2px 0px 0px;
            border-color: @separatorcolor;
            spacing:      10px;
            scrollbar:    true;
            padding:      2px 0px 0px;
        }
        mainbox {
            border:  0;
            padding: 0;
        }
        message {
            border:       2px 0px 0px;
            border-color: @separatorcolor;
            padding:      1px;
        }
        ${commonLayoutStyles}
      '';

      # Power menu config (powermenu.rasi)
      powermenuConfig = ''
        /* Power menu - east sidebar, 7 lines, no inputbar */
        @import "config"

        window {
            background-color: @background;
            border:           0;
            padding:          10;
            transparency:     "real";
            width:            120px;
            location:         east;
        }
        listview {
            lines:     7;
            columns:   1;
            scrollbar: false;
        }
        mainbox {
            children: [listview];
        }
        ${commonLayoutStyles}
      '';

      # Power profiles config (power-profiles.rasi)
      powerProfilesConfig = ''
        /* Power profile selector - east sidebar, 4 lines */
        @import "config"

        window {
            background-color: @background;
            border:           0;
            padding:          10;
            transparency:     "real";
            width:            170px;
            location:         east;
        }
        listview {
            lines:   4;
            columns: 1;
        }
        ${commonLayoutStyles}
        textbox-prompt-colon {
            str: "Set Power Profile:";
        }
      '';

      # Keyhint menu config (rofikeyhint.rasi)
      rofikeyhintConfig = ''
        /* Keybinding hints - 1 column, 10 lines */
        @import "config"

        window {
            background-color: @background;
            border:           0;
            padding:          30;
        }
        listview {
            lines:        10;
            columns:      1;
            fixed-height: 0;
            border:       8px 0px 0px;
            border-color: @separatorcolor;
            spacing:      8px;
            scrollbar:    false;
            padding:      2px 0px 0px;
        }
        mainbox {
            border:  0;
            padding: 0;
        }
        message {
            border:       2px 0px 0px;
            border-color: @separatorcolor;
            padding:      1px;
        }
        ${commonLayoutStyles}
      '';
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.rofi = {
          enable = true;

          # Terminal for running console applications
          inherit terminal;

          # Calculator plugin (uses libqalculate)
          plugins = [ pkgs.rofi-calc ];

          # Enable modes
          modes = [
            "window"
            "drun"
            "run"
            "ssh"
            "combi"
            "filebrowser"
            "calc"
          ];

          # Additional configuration matching old config.rasi
          extraConfig = {
            # Display settings
            show-icons = true;
            icon-theme = config.gtk.iconTheme.name or "hicolor";

            # Display format with icons
            display-ssh = " ";
            display-run = " ";
            display-drun = "⚙ ";
            display-window = " ";
            display-combi = " ";

            # Combi mode settings
            combi-modes = "window,drun,ssh";
            combi-display-format = "{mode} {text}";
            combi-hide-mode-prefix = false;

            # General settings
            drun-display-format = "{name}";
            disable-history = false;
            scroll-method = 0;
            sidebar-mode = false;
            hide-scrollbar = false;

            # Cache directory
            cache-dir = "~/.cache/rofi";

            # Filebrowser settings
            filebrowser-directories-first = true;
            filebrowser-sorting-method = "name";
          };

          # Theme is set by stylix - it creates ~/.local/share/rofi/themes/custom.rasi
          # with all the base16 color definitions
        };

        # Install config files that import the main config (which has stylix theme)
        xdg.configFile = {
          "rofi/rofidmenu.rasi".text = rofidmenuConfig;
          "rofi/powermenu.rasi".text = powermenuConfig;
          "rofi/power-profiles.rasi".text = powerProfilesConfig;
          "rofi/rofikeyhint.rasi".text = rofikeyhintConfig;
        };
      };
    };
}
