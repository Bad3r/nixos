# Module: home/base/git/diff.nix
# Purpose: Git version control configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base.programs.git = {
    difftastic = {
      enable = true;
      background = "dark";
    };
    extraConfig.diff.algorithm = "histogram";
  };
}
