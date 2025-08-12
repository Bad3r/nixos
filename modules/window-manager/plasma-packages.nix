{ ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {  # KDE applications are PC features
    environment.systemPackages = with pkgs.kdePackages; [
      # Core KDE Applications
      kate                # Text editor
      kdenlive           # Video editor
      kcalc              # Calculator
      kcolorchooser      # Color picker
      ark                # Archive manager
      kdeconnect-kde     # Phone integration
      partitionmanager   # Disk management
      filelight          # Disk usage analyzer
      spectacle          # Screenshot tool
      gwenview          # Image viewer
      okular            # Document viewer
      
      # Additional KDE utilities
      kcharselect       # Character selector
      kfind             # File search
      kruler            # Screen ruler
      kwalletmanager    # Wallet management
      ktimer            # Timer
      sweeper           # System cleaner
    ];
  };
}