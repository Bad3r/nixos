{
  # Home Manager i3 keybindings for common actions
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      xsession = {
        enable = true;
        windowManager.i3 = {
          enable = true;
          config =
            let
              # Resolve the configured modifier (e.g., "Mod4").
              mod = config.xsession.windowManager.i3.config.modifier;
            in
            {
              # Use Super as the i3 modifier. Home Manager expands this to e.g. "Mod4".
              modifier = lib.mkDefault "Mod4";

              # Keybindings requested (use resolved modifier, not "$mod").
              keybindings = {
                # super + Enter = new default terminal window (kitty)
                "${mod}+Return" = "exec ${lib.getExe pkgs.kitty}";

                # control + shift + q = close window
                # i3 expects the modifier name "Control" (not "Ctrl")
                "Control+Shift+q" = "kill";

                # super + d = run rofi (application launcher)
                "${mod}+d" = "exec ${lib.getExe pkgs.rofi} -modi drun -show drun";
              };
            };
        };
      };
    };
}
