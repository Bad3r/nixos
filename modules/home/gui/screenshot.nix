
{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    let
      shotman = "${pkgs.shotman}/bin/shotman --capture";
    in
    {
      # Install screenshot tools for both Wayland and X11
      home.packages = with pkgs; [
        flameshot  # X11 screenshot tool
        shotman    # Wayland screenshot tool
      ];
      
      # Wayland/Sway keybindings
      wayland.windowManager.sway.config.keybindings = {
        "Mod4+Shift+w" = "exec ${shotman} window";
        "Mod4+Shift+o" = "exec ${shotman} output";
        "Mod4+Shift+r" = "exec ${shotman} region";
      };
      
      # Note: X11 users can use flameshot with:
      # flameshot gui - Interactive screenshot
      # flameshot full - Full screen screenshot
      # flameshot screen - Current screen screenshot
    };
}
