{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      programs.kitty.enable = true;
    };
}
