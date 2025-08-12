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
      allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "vscode"
        "discord"
        "slack"
        "zoom"
        "spotify"
        "logseq"
      ];
    };
  };
}