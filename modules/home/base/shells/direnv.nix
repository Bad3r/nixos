# Module: home/base/shells/direnv.nix
# Purpose: Git version control configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base = {
    programs = {
      direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.global.warn_timeout = 0;
      };
      git.ignores = [
        ".envrc"
        ".direnv"
      ];
    };
  };
}
