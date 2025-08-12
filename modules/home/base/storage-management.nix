# Module: home/base/storage-management.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [ gptfdisk ];
    };
}
