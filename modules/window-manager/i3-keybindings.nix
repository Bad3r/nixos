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
            # Use Super/Mod4 as the i3 modifier ("$mod")
            modifier = lib.mkDefault "Mod4";

            # Keybindings requested
            keybindings = {
              # super + Enter = new default terminal window (kitty)
              "$mod+Return" = "exec ${lib.getExe pkgs.kitty}";

              # ctrl + shift + q = close window
              # Accept both Control/Ctrl naming variants
              "Control+Shift+q" = "kill";
              "Ctrl+Shift+q" = "kill";

              # super + d = run rofi (application launcher)
              "$mod+d" = "exec ${lib.getExe pkgs.rofi} -modi drun -show drun";
            };
          };
        };
      };
    };
}
