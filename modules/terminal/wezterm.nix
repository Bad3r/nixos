{
  flake.homeManagerModules.gui =
    { lib, ... }:
    {
      # Enable Stylix theming for wezterm
      stylix.targets.wezterm.enable = lib.mkDefault true;

      programs.wezterm.enable = true;
    };
}
