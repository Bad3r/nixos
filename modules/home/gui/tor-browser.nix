# Module: home/gui/tor-browser.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.gui
# Pattern: Home Manager GUI - Graphical application configuration

{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [ tor-browser-bundle-bin ];
    };
}
