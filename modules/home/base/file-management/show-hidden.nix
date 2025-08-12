# Module: home/base/file-management/show-hidden.nix
# Purpose: Show Hidden configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base = {
    programs.yazi.settings.mgr.show_hidden = true;
  };
}
