# Note: This only handles user-level theming, system theming is in base/stylix-nixos.nix

{ inputs, lib, ... }:
{
  flake.modules.homeManager.base = {
    imports = [ inputs.stylix.homeModules.stylix ];
    
    stylix.enable = lib.mkDefault true;
  };
}