# Module: custom-packages.nix
# Purpose: Custom package definitions and overrides for workstation
# Pattern: Extends workstation namespace as these are developer tools
# Dependencies: None

{ config, lib, ... }:
{
  # Custom packages for workstation environments
  # These extend the workstation namespace, not create a new named module
  flake.modules.nixos.workstation = { pkgs, ... }: {
    # Custom packages that need special handling
    environment.systemPackages = with pkgs; lib.mkDefault [
      logseq  # Note-taking application
      # Add more custom packages here as needed
    ];
    
    # Package overrides
    nixpkgs.config = {
      # Allow specific unfree packages
      allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "vscode"
        "vscode-fhs"
        "discord"
        "slack"
        "zoom"
        "spotify"
        "steam"
        "steam-original"
        "steam-run"
      ];
    };
  };
}