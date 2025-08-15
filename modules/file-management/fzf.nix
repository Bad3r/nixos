{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
        enableBashIntegration = true;
        enableFishIntegration = true;
      };
    };
}
