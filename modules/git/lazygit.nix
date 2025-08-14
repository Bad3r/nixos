{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      programs.lazygit.enable = true;
    };
}
