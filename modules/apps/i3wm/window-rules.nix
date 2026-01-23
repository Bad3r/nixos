# i3 window rules configuration
# Defines workspace assignments and per-window commands
{
  flake.homeManagerModules.apps.i3-config =
    { config, lib, ... }:
    let
      cfg = config.gui.i3;

      # Quarter-screen corner commands (resize + position)
      topRight = "resize set ${cfg.quarterSize}, move position ${cfg.quarterPosition}";
    in
    {
      options.gui.i3 = {
        quarterSize = lib.mkOption {
          type = lib.types.str;
          default = "1270 695";
          description = ''
            Quarter-screen window dimensions as "width height" in pixels.
            Default is calculated for 2560x1440: (2560/2 - 10) x (1440/2 - 25).
          '';
        };

        quarterPosition = lib.mkOption {
          type = lib.types.str;
          default = "1285 px 34 px";
          description = ''
            Top-right quarter position as "x px y px".
            Default is calculated for 2560x1440: x = 2560/2 + 5, y = 34 (bar offset).
          '';
        };
      };

      config.xsession.windowManager.i3.config = {
        # Workspace assignments by window class
        assigns = lib.mkOptionDefault {
          "2" = [ { class = "(?i)^${cfg.browserClass}$"; } ];
          "3" = [ { class = "(?i)^thunar$"; } ];
        };

        # Per-window commands (floating, resize, position, borders)
        window.commands = [
          # Window type rules
          {
            criteria.window_type = "dialog";
            command = "floating enable, focus";
          }
          {
            criteria.window_type = "utility";
            command = "floating enable";
          }
          # Window role rules
          {
            criteria.window_role = "(?i)^pop-?up$";
            command = "floating enable";
          }
          {
            criteria.window_role = "(?i)^toolbox$";
            command = "floating enable";
          }
          # Specific window rules
          {
            criteria.class = "(?i)^(?:qt5ct|pinentry)$";
            command = "floating enable, focus";
          }
          {
            criteria.class = "(?i)^claude-wpa$";
            command = "floating enable, ${topRight}";
          }
          {
            # bitwarden desktop app: NORMAL type, needs floating
            criteria.class = "(?i)^bitwarden$";
            command = "floating enable, ${topRight}";
          }
          {
            # bitwarden browser extension: dialog + title for positioning
            criteria = {
              window_type = "dialog";
              title = "(?i)Extension:.*Bitwarden";
            };
            command = topRight;
          }
          {
            # pwvucontrol: NORMAL type, needs floating
            criteria.class = "(?i)^pwvucontrol$";
            command = "floating enable, ${topRight}";
          }
          {
            criteria.class = "(?i)^devtools$";
            command = "floating enable, ${topRight}";
          }
          {
            criteria.class = "(?i)^protonvpn-app$";
            command = "floating enable";
          }
          # Float Thunar progress dialogs (title is substring match)
          {
            criteria = {
              class = "(?i)^thunar$";
              title = "(?i)(?:copying|deleting|moving)";
            };
            command = "floating enable";
          }
          # Focus urgent windows
          {
            criteria.urgent = "latest";
            command = "focus";
          }
          # Default styling for all windows
          {
            criteria.all = true;
            command = ''border pixel 5, title_format "<b>%title</b>", title_window_icon padding 3px'';
          }
        ];
      };
    };
}
