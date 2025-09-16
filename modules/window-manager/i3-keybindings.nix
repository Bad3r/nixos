{
  # Home Manager i3 keybindings for common actions
  flake.homeManagerModules.gui =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      xsession = {
        enable = true;
        windowManager.i3 = {
          enable = true;
          config = {
            # Use super as the i3 modifier ("$mod"). Under the hood $mod defaults to Mod4.
            modifier = lib.mkDefault "Mod4";

            # Keybindings requested
            keybindings =
              let
                normalizeMap = config.flake.lib.homeManager.i3.normalizeMap or (attrs: attrs);
              in
              normalizeMap {
                # super + Enter = new default terminal window (kitty)
                "$mod+Return" = "exec ${lib.getExe pkgs.kitty}";

                # ctrl + shift + q = close window (canonicalized to Ctrl+Shift+q)
                "Ctrl+Shift+q" = "kill";

                # super + d = run rofi (application launcher)
                "$mod+d" = "exec ${lib.getExe pkgs.rofi} -modi drun -show drun";
              };
          };
        };
      };
    };
}
