# Module: stylix-nix-on-droid.nix
# Purpose: Nix-on-Droid stylix theming configuration
# Namespace: flake.modules.nixOnDroid.base
# Dependencies: inputs.stylix
# Note: Specific to Nix-on-Droid environments

{ inputs, lib, ... }:
{
  flake.modules.nixOnDroid.base = {
    imports = [ inputs.stylix.nixOnDroidModules.stylix ];
    
    stylix.enable = lib.mkDefault true;
  };
}