{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      programs.bat.enable = true;
      programs.eza.enable = true;
    };
}
