# Module: home/base/file-management/search.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.fd
        pkgs.ripgrep
        pkgs.ripgrep-all
      ];
    };
}
