# Module: home/gui/windows.nix
# Purpose: Windows configuration
# Namespace: flake.modules.homeManager.gui
# Pattern: Home Manager GUI - Graphical application configuration

{
  flake.modules.homeManager.gui = {
    wayland.windowManager.hyprland.settings.decoration.rounding = 5;
  };
}
