{
  flake.modules.homeManager.base = _: {
    programs.bat.enable = true;
    programs.eza.enable = true;
  };
}
