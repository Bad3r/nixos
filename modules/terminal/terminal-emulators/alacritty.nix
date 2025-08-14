{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      programs.alacritty.enable = true;
    };
}
