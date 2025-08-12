# Module: home/base/shells/fish.nix
# Purpose: Shell environment and configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base.programs.fish = {
    enable = true;
  };
}
