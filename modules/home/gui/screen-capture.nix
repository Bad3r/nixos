# Module: home/gui/screen-capture.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.gui
# Pattern: Home Manager GUI - Graphical application configuration

# modules/screen-capture.nix

{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.kooha ];
    };
}
