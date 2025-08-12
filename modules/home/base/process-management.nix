# Module: home/base/process-management.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

# modules/process-management.nix

{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        lsof
        procs
        psmisc
        watchexec
        htop
      ];

      programs.bottom = {
        enable = true;
        settings = {
          rate = 400;
        };
      };
    };
}
