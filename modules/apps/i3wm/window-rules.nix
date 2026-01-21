# i3 window rules configuration
# Defines workspace assignments, floating criteria, and per-window commands
{
  flake.homeManagerModules.apps.i3-config =
    { config, lib, ... }:
    {
      config.xsession.windowManager.i3.config = {
        # Workspace assignments by window class
        assigns = lib.mkOptionDefault {
          "1" = [ { class = "(?i)(?:geany)"; } ];
          "2" = [ { class = "(?i)(?:${config.gui.i3.browserClass})"; } ];
          "3" = [ { class = "(?i)(?:thunar)"; } ];
        };

        # Windows that should automatically float
        floating.criteria = [
          { class = "(?i)(?:qt5ct|pinentry)"; }
          { class = "claude-wpa"; }
          { class = "(?i)protonvpn-app"; }
          {
            class = "Thunar";
            title = "(?i)(?:copying|deleting|moving)";
          }
          { class = "(?i)bitwarden"; }
          { window_role = "(?i)(?:pop-up|setup)"; }
        ];

        # Per-window commands (floating, resize, position, borders)
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
          {
            criteria = {
              class = "claude-wpa";
            };
            command = "floating enable, resize set 1270 695, move position center";
          }
          {
            criteria = {
              class = "(?i)bitwarden";
            };
            command = "floating enable, resize set 1270 694, move position 1285 px 36 px";
          }
          {
            criteria = {
              class = "pwvucontrol";
            };
            command = "floating enable, resize set 1270 695, move position 1285 px 34 px";
          }
          {
            criteria = {
              class = "Devtools";
            };
            command = "floating enable, resize set 1270 695, move position 1285 px 34 px";
          }
          {
            criteria = {
              all = true;
            };
            command = ''border pixel 5, title_format "<b>%title</b>", title_window_icon padding 3px'';
          }
        ];
      };
    };
}
