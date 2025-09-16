{
  # Home Manager i3 keybindings for common actions
  flake.homeManagerModules.gui =
    { pkgs, lib, ... }:
    {
      xsession = {
        enable = true;
        windowManager.i3 = {
          enable = true;
          config = {
            # Use super as the i3 modifier ("$mod"). Under the hood $mod defaults to Mod4.
            modifier = lib.mkDefault "Mod4";

            # Keybindings requested
            keybindings = {
              # super + Enter = new default terminal window (kitty)
              "$mod+Return" = "exec ${lib.getExe pkgs.kitty}";

              # control + shift + q = close window
              # i3 expects the modifier name "Control" (not "Ctrl")
              "Control+Shift+q" = "kill";

              # super + d = run rofi (application launcher)
              "$mod+d" = "exec ${lib.getExe pkgs.rofi} -modi drun -show drun";
            };
          };
        };
      };
    };
}
