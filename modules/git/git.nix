{
  flake.homeManagerModules.base = {
    programs = {
      git.enable = true;
      delta = {
        enable = true;
        enableGitIntegration = true;
      };
    };
  };
}
