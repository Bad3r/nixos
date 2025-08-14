{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      programs.wezterm.enable = true;
    };
}
