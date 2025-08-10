# Module: stylix-home.nix
# Purpose: Home-Manager user-level stylix theming configuration
# Namespace: flake.modules.homeManager.base
# Dependencies: inputs.stylix
# Note: This only handles user-level theming, system theming is in base/stylix-nixos.nix

{ inputs, lib, ... }:
{
  flake.modules.homeManager.base = {
    imports = [ inputs.stylix.homeModules.stylix ];
    
    stylix.enable = lib.mkDefault true;
  };
}