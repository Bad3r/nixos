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
    * Modes: window, drun, run, ssh, combi, file-browser, calc
    * Terminal integration for running console applications

  Config files installed:
    * ~/.config/rofi/rofidmenu.rasi      - Apps menu layout (3 columns, 10 lines)
    * ~/.config/rofi/powermenu.rasi      - Power menu layout (east sidebar, 7 lines)
    * ~/.config/rofi/power-profiles.rasi - Power profile selector (east, 4 lines)
    * ~/.config/rofi/rofikeyhint.rasi    - Keybinding hints (1 column, 10 lines)

  Example Usage:
    * `rofi -show drun` — Default app launcher with stylix colors.
    * `rofi -config ~/.config/rofi/rofidmenu.rasi -show drun` — Apps in 3-column grid.
    * `echo -e "Shutdown\nRestart" | rofi -dmenu -config ~/.config/rofi/powermenu.rasi` — Power menu.
    * `rofi -config ~/.config/rofi/rofikeyhint.rasi -show keys` — Show keybindings.
*/

{ lib, ... }:
{
  flake.homeManagerModules.apps.rofi =
    {
      config,
      pkgs,
      ...
    }:
    let
      # Get terminal from i3 commands if available, fallback to kitty
      terminal =
        let
          i3Commands = lib.attrByPath [ "gui" "i3" "commands" ] { } config;
        in
        i3Commands.terminal or "${lib.getExe pkgs.kitty}";

      # Common element styles that reference stylix color variables
      # These use @variable references that stylix defines in the base theme
      commonElementStyles = ''
        element {
            border:  0;
            padding: 1px;
        }
        element-text {
            background-color: inherit;
            text-color:       inherit;
        }
        element.normal.normal {
            background-color: @normal-background;
            text-color:       @normal-foreground;
        }
        element.normal.urgent {
            background-color: @urgent-background;
            text-color:       @urgent-foreground;
        }
        element.normal.active {
            background-color: @active-background;
            text-color:       @active-foreground;
        }
        element.selected.normal {
            background-color: @selected-normal-background;
            text-color:       @selected-normal-foreground;
        }
        element.selected.urgent {
            background-color: @selected-urgent-background;
            text-color:       @selected-urgent-foreground;
        }
        element.selected.active {
            background-color: @selected-active-background;
            text-color:       @selected-active-foreground;
        }
        element.alternate.normal {
            background-color: @alternate-normal-background;
            text-color:       @alternate-normal-foreground;
        }
        element.alternate.urgent {
            background-color: @alternate-urgent-background;
            text-color:       @alternate-urgent-foreground;
        }
        element.alternate.active {
            background-color: @alternate-active-background;
            text-color:       @alternate-active-foreground;
        }
        scrollbar {
            width:        4px;
            border:       0;
            handle-color: @normal-foreground;
            handle-width: 8px;
            padding:      0;
        }
        mode-switcher {
            border:       2px 0px 0px;
            border-color: @separatorcolor;
        }
        button {
            spacing:    0;
            text-color: @normal-foreground;
        }
        button.selected {
            background-color: @selected-normal-background;
            text-color:       @selected-normal-foreground;
        }
        inputbar {
            spacing:    0;
            text-color: @normal-foreground;
            padding:    1px;
            children:   [ prompt,textbox-prompt-colon,entry,case-indicator ];
        }
        case-indicator {
            spacing:    0;
            text-color: @normal-foreground;
        }
        entry {
            spacing:    0;
            text-color: @normal-foreground;
        }
        prompt {
            spacing:    0;
            text-color: @normal-foreground;
        }
        textbox-prompt-colon {
            expand:     false;
            str:        ":";
            margin:     0px 0.3em 0em 0em;
            text-color: @normal-foreground;
        }
      '';

      # Apps menu config (rofidmenu.rasi)
      # Imports main config.rasi for stylix colors, then overrides layout
      rofidmenuConfig = ''
        /* Apps menu - 3 columns, 10 lines */
        @import "config"

        window {
            background-color: @background;
            border:           5;
            border-color:     @border-color;
            padding:          30;
        }
        listview {
            lines:        10;
            columns:      3;
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
        textbox {
            text-color: @foreground;
        }
        ${commonElementStyles}
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
        ${commonElementStyles}
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
        ${commonElementStyles}
        textbox-prompt-colon {
            expand:     false;
            str:        "Set Power Profile:";
            margin:     0px 0.3em 0em 0em;
            text-color: @normal-foreground;
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
        textbox {
            text-color: @foreground;
        }
        ${commonElementStyles}
      '';
    in
    {
      programs.rofi = {
        enable = true;

        # Terminal for running console applications
        inherit terminal;

        # Enable modes
        modes = [
          "window"
          "drun"
          "run"
          "ssh"
          "combi"
          "filebrowser"
        ];

        # Additional configuration matching old config.rasi
        extraConfig = {
          # Display settings
          show-icons = true;
          icon-theme = "Qogir-dark";

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
          hide-scrollbar = true;

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
}
