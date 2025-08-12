# Module: pc/nix-community.nix
# Purpose: Nix Community configuration
# Namespace: flake.modules.nixos.pc
# Pattern: Personal computer configuration - Extends base for desktop systems

# modules/nix-community.nix

{
  flake.modules.nixos.pc.nix.settings = {
    substituters = [ "https://nix-community.cachix.org" ];
    trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };
}
