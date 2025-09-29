{
  flake.homeManagerModules.base = _: {
    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableFishIntegration = false;
    };
  };
}
