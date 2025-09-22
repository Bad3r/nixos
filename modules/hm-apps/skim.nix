{
  flake.homeManagerModules.apps.skim = _: {
    programs.skim = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };
  };
}
