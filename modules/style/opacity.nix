# Module: style/opacity.nix
# Purpose: Opacity configuration
# Namespace: flake.modules.nixos.style
# Pattern: Styling configuration - System-wide theming and appearance

{ lib, ... }:
let
  polyModule = {
    stylix.opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (n: 0.85);
  };
in
{
  flake.modules = {
    nixos.pc = polyModule;
    homeManager.gui = polyModule;
    nixOnDroid.base = polyModule;
  };
}
