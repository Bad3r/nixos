# Module: home/base/file-management/yazi.nix
# Purpose: Yazi configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base = {
    programs.yazi.enable = true;
  };
}
