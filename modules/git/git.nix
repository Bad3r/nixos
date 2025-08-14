{
  flake.modules.homeManager.base = {
    programs.git = {
      enable = true;
      delta.enable = true;
    };
  };
}
