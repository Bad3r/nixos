/*
  Package: rofi
  Description: Window switcher, application launcher, and dmenu replacement with plugin system.
  Homepage: https://github.com/davatorium/rofi
  Documentation: https://github.com/davatorium/rofi/blob/next/doc/rofi.1.md
  Repository: https://github.com/davatorium/rofi

  Summary:
    * Provides a customizable launcher supporting modes for running applications, switching windows, SSH, scripts, file browsers, and more.
    * Features themes, keybinding customization, history, and scriptable "modi" to extend functionality beyond launching apps.
    * Styled after the VS Code command palette, colored from the Stylix palette.

  Features:
    * VS Code command palette look: top-centered 600px box, rounded input, solid selected row
    * Multiple specialized themes: dmenu (apps), powermenu, power-profiles, keyhint
    * Modes: window, drun, run, ssh, combi, filebrowser, calc
    * Calculator mode via rofi-calc plugin (uses libqalculate for natural language math)
    * Terminal integration for running console applications

  Config files installed:
    * ~/.config/rofi/rofidmenu.rasi      - Apps menu (command palette, 12 lines)
    * ~/.config/rofi/powermenu.rasi      - Power menu layout (east sidebar, 7 lines)
    * ~/.config/rofi/power-profiles.rasi - Power profile selector (east, 4 lines)
    * ~/.config/rofi/rofikeyhint.rasi    - Keybinding hints (1 column, 10 lines)

  Example Usage:
    * `rofi -show drun` -- App launcher in the command palette style.
    * `rofi -config ~/.config/rofi/rofidmenu.rasi -show drun` -- Apps menu with its own placeholder.
    * `rofi -show calc -modi calc -no-show-match -no-sort` -- Calculator with natural language.
    * `echo -e "Shutdown\nRestart" | rofi -dmenu -config ~/.config/rofi/powermenu.rasi` -- Power menu.
    * `rofi -config ~/.config/rofi/rofikeyhint.rasi -show keys` -- Show keybindings.
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

      inherit (config.lib.formats.rasi) mkLiteral;
      colors = config.lib.stylix.colors.withHashtag;
      # VS Code Dark 2026 quickInput colors with no base16 slot.
      palette = {
        background = "#202122"; # quickInput.background
        focusBorder = "#3994bcb3"; # focusBorder
        placeholder = "#555555"; # input.placeholderForeground
        selection = "#297aa0"; # quickInputList.focusBackground
        selectionText = "#ffffff"; # quickInputList.focusForeground
        match = "#48a0c7"; # list.highlightForeground
      };

      # VS Code command palette (quick input), from workbench CSS: 600px wide,
      # 12px window radius, 6px input radius, 22px rows with 3px radius.
      commandPaletteTheme = {
        "*" = {
          background-color = mkLiteral "transparent";
          text-color = mkLiteral colors.base05;
          # Named colors read by the other .rasi files.
          background = mkLiteral palette.background;
          foreground = mkLiteral colors.base05;
          border-color = mkLiteral colors.base02;
          separatorcolor = mkLiteral colors.base02;
        };
        window = {
          location = mkLiteral "north";
          anchor = mkLiteral "north";
          y-offset = mkLiteral "8%";
          width = mkLiteral "600px";
          background-color = mkLiteral palette.background;
          border = mkLiteral "1px";
          border-color = mkLiteral colors.base02;
          border-radius = mkLiteral "12px";
          padding = mkLiteral "6px";
          transparency = "real";
        };
        mainbox = {
          spacing = mkLiteral "4px";
          children = map mkLiteral [
            "inputbar"
            "message"
            "listview"
          ];
        };
        inputbar = {
          children = map mkLiteral [ "entry" ];
          background-color = mkLiteral colors.base01;
          border = mkLiteral "1px";
          border-color = mkLiteral palette.focusBorder;
          border-radius = mkLiteral "6px";
          padding = mkLiteral "4px 6px";
        };
        entry = {
          placeholder = "Type to search";
          placeholder-color = mkLiteral palette.placeholder;
          cursor = mkLiteral "text";
        };
        message = {
          padding = mkLiteral "4px 6px";
        };
        textbox = {
          text-color = mkLiteral colors.base04;
        };
        listview = {
          lines = 12;
          fixed-height = false;
          dynamic = true;
          scrollbar = false;
          spacing = mkLiteral "0px";
          padding = mkLiteral "0px 0px 2px";
        };
        element = {
          padding = mkLiteral "3px 6px";
          spacing = mkLiteral "6px";
          border-radius = mkLiteral "3px";
        };
        "element normal.normal" = {
          text-color = mkLiteral colors.base05;
        };
        "element alternate.normal" = {
          text-color = mkLiteral colors.base05;
        };
        "element normal.active" = {
          text-color = mkLiteral colors.base0D;
        };
        "element alternate.active" = {
          text-color = mkLiteral colors.base0D;
        };
        "element normal.urgent" = {
          text-color = mkLiteral colors.base08;
        };
        "element alternate.urgent" = {
          text-color = mkLiteral colors.base08;
        };
        "element selected.normal" = {
          background-color = mkLiteral palette.selection;
          text-color = mkLiteral palette.selectionText;
        };
        "element selected.active" = {
          background-color = mkLiteral palette.selection;
          text-color = mkLiteral palette.selectionText;
        };
        "element selected.urgent" = {
          background-color = mkLiteral colors.base08;
          text-color = mkLiteral palette.selectionText;
        };
        element-icon = {
          size = mkLiteral "16px";
        };
        element-text = {
          text-color = mkLiteral "inherit";
          highlight = mkLiteral "bold ${palette.match}";
          vertical-align = mkLiteral "0.5";
        };
        "element-text selected" = {
          highlight = mkLiteral "bold ${palette.selectionText}";
        };
      };

      # Layout-only styles for the sidebar menus
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
      rofidmenuConfig = ''
        /* Apps menu - command palette */
        @import "config"

        entry {
            placeholder: "Search applications";
        }
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
            anchor:           east;
            y-offset:         0;
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
            anchor:           east;
            y-offset:         0;
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
          package = lib.attrByPath [ "programs" "rofi" "extended" "package" ] pkgs.rofi osConfig;

          # Calculator plugin (uses libqalculate)
          plugins = [ pkgs.rofi-calc ];

          settings = {
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
              "calc"
            ];

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

          font = "${config.stylix.fonts.sansSerif.name} ${toString config.stylix.fonts.sizes.popups}";
          theme = commandPaletteTheme;
        };

        stylix.targets.rofi.enable = false;

        # Install config files that import the main config (which has the theme)
        xdg.configFile = {
          "rofi/rofidmenu.rasi".text = rofidmenuConfig;
          "rofi/powermenu.rasi".text = powermenuConfig;
          "rofi/power-profiles.rasi".text = powerProfilesConfig;
          "rofi/rofikeyhint.rasi".text = rofikeyhintConfig;
        };
      };
    };
}
