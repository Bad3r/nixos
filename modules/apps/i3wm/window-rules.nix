# i3 window rules configuration
# Defines workspace assignments and per-window commands
{
  flake.homeManagerModules.apps.i3-config =
    { config, lib, ... }:
    let
      cfg = config.gui.i3;

      # Quarter-screen geometry calculations (all derived from config options)
      # Width:  screenWidth/2 - borderWidth*2  (gap on both sides of center split)
      # Height: screenHeight/2 - fontSize*2 - 1  (account for bar area)
      # X:      screenWidth/2 + borderWidth  (start just past center)
      # Y:      barHeight  (start below status bar)
      qWidth = toString ((cfg.screenWidth / 2) - (cfg.borderWidth * 2));
      qHeight = toString ((cfg.screenHeight / 2) - (cfg.fontSize * 2) - 1);
      xPos = toString ((cfg.screenWidth / 2) + cfg.borderWidth);
      yPos = toString cfg.barHeight;

      # Quarter-screen top-right corner with exact pixel positioning
      topRight = "resize set ${qWidth} px ${qHeight} px, move position ${xPos} px ${yPos} px";

      # ProtonVPN window positioning (known size: 408x600)
      protonvpnX = toString (cfg.screenWidth - 408 - (cfg.borderWidth * 2) - 1);
    in
    {

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
            criteria.class = "(?i)^bitwarden$";
            command = "floating enable, ${topRight}";
          }
          {
            # Bitwarden browser extension popup window
            criteria = {
              window_type = "dialog";
              title = "(?i)Extension:.*Bitwarden";
            };
            command = topRight;
          }
          {
            # Pipewire Volume Control
            criteria.class = "(?i)^pwvucontrol$";
            command = "floating enable, ${topRight}";
          }
          {
            # Browser DevTools
            criteria.class = "(?i)^devtools$";
            command = "floating enable, ${topRight}";
          }
          {
            criteria.class = "(?i)^protonvpn-app$";
            command = "floating enable, move position ${protonvpnX} px ${yPos} px";
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
