# Module: home/base/git/conflicts.nix
# Purpose: Git version control configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base.programs.git = {
    extraConfig = {
      merge.conflictstyle = "zdiff3";
      rerere.enabled = true;
    };
  };
}
