/*
  Package: rofi
  Description: Window switcher, application launcher, and dmenu replacement with plugin system.
  Homepage: https://github.com/davatorium/rofi
  Documentation: https://github.com/davatorium/rofi/blob/next/doc/rofi.1.md
  Repository: https://github.com/davatorium/rofi

  Summary:
    * Provides a customizable launcher supporting modes for running applications, switching windows, SSH, scripts, file browsers, and more.
    * Features themes, keybinding customization, history, and scriptable "modi" to extend functionality beyond launching apps.
    * Spotlight-style layout in VS Code Dark 2026 colors, from the Stylix palette.

  Features:
    * macOS Spotlight proportions: centered 680px box, large search field, roomy rows
    * Multiple specialized themes: dmenu (apps), powermenu, power-profiles, keyhint
    * Modes: window, drun, run, ssh, combi, filebrowser, calc
    * Calculator mode via rofi-calc plugin (uses libqalculate for natural language math)
    * Terminal integration for running console applications

  Config files installed:
    * ~/.config/rofi/rofidmenu.rasi      - Apps menu (Spotlight layout, 9 lines)
    * ~/.config/rofi/powermenu.rasi      - Power menu (Spotlight layout, 7 lines)
    * ~/.config/rofi/power-profiles.rasi - Power profile selector (Spotlight layout, 3 lines)
    * ~/.config/rofi/rofikeyhint.rasi    - Keybinding hints (Spotlight layout, 10 lines)

  Example Usage:
    * `rofi -show drun` -- App launcher in the Spotlight layout.
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
      windowRadius = 18;

      # VS Code Dark 2026 quickInput colors with no base16 slot.
      palette = {
        background = "#202122"; # quickInput.background
        # VS Code's frosted glass: the surface at 92% over a backdrop blur.
        glass = "#202122eb";
        placeholder = "#555555"; # input.placeholderForeground
        selection = "#297aa0"; # quickInputList.focusBackground
        selectionText = "#ffffff"; # quickInputList.focusForeground
        match = "#48a0c7"; # list.highlightForeground
      };

      # macOS Spotlight layout: centered box, large search field with a
      # magnifier, hairline under the field, roomy rows with large icons.
      launcherTheme = {
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
          # Top edge just above center, so the field stays put while results
          # grow downward and a full list sits centered.
          location = mkLiteral "center";
          anchor = mkLiteral "north";
          y-offset = mkLiteral "-15%";
          width = mkLiteral "680px";
          background-color = mkLiteral palette.glass;
          border = mkLiteral "1px";
          border-color = mkLiteral colors.base02;
          border-radius = mkLiteral "${toString windowRadius}px";
          padding = mkLiteral "10px";
          transparency = "real";
        };
        # The separator and gap belong to the listview, which rofi collapses to
        # zero height (margin and border included) when nothing matches.
        mainbox = {
          spacing = mkLiteral "0px";
          children = map mkLiteral [
            "inputbar"
            "message"
            "listview"
          ];
        };
        inputbar = {
          children = map mkLiteral [
            "icon-search"
            "entry"
          ];
          spacing = mkLiteral "10px";
          padding = mkLiteral "6px 8px";
        };
        icon-search = {
          expand = false;
          filename = "${config.lib.stylix.colors {
            template = builtins.readFile ../../stylix/icons/search.svg.mustache;
            extension = ".svg";
          }}";
          size = mkLiteral "22px";
          vertical-align = mkLiteral "0.5";
        };
        entry = {
          font = "${config.stylix.fonts.sansSerif.name} 16";
          placeholder = "Search";
          placeholder-color = mkLiteral palette.placeholder;
          vertical-align = mkLiteral "0.5";
          cursor = mkLiteral "text";
        };
        message = {
          padding = mkLiteral "4px 6px";
        };
        textbox = {
          text-color = mkLiteral colors.base04;
        };
        listview = {
          lines = 9;
          fixed-height = false;
          dynamic = true;
          scrollbar = false;
          spacing = mkLiteral "0px";
          margin = mkLiteral "6px 0px 0px";
          border = mkLiteral "1px 0px 0px";
          border-color = mkLiteral colors.base02;
          padding = mkLiteral "8px 0px 0px";
        };
        element = {
          padding = mkLiteral "6px 10px";
          spacing = mkLiteral "10px";
          border-radius = mkLiteral "8px";
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
          size = mkLiteral "24px";
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

      # Apps menu config (rofidmenu.rasi)
      rofidmenuConfig = ''
        /* Apps menu - Spotlight layout */
        @import "config"

        entry {
            placeholder: "Search applications";
        }
      '';

      # Session power menu (powermenu.rasi)
      powermenuConfig = ''
        /* Power menu - Spotlight layout */
        @import "config"

        entry {
            placeholder: "Power";
        }
        listview {
            lines: 7;
        }
      '';

      # Power profile selector (power-profiles.rasi)
      powerProfilesConfig = ''
        /* Power profile selector - Spotlight layout */
        @import "config"

        entry {
            placeholder: "Power profile";
        }
        listview {
            lines: 3;
        }
      '';

      # Keybinding hints (rofikeyhint.rasi)
      rofikeyhintConfig = ''
        /* Keybinding hints - Spotlight layout */
        @import "config"

        entry {
            placeholder: "Search keybindings";
        }
        listview {
            lines: 10;
        }
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
          theme = launcherTheme;
        };

        stylix.targets.rofi.enable = false;

        # picom blurs and rounds the window at the theme's radius.
        services.picom.settings.corner-radius-rules = [ "${toString windowRadius}:class_g = 'Rofi'" ];

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
