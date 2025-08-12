# Module: home/base/file-management/space-usage.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.du-dust ];
    };
}
