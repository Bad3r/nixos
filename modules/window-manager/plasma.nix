
# KDE Plasma Desktop Configuration (Simplified)
{ config, lib, ... }:
{
  # System-level Plasma configuration
  flake.modules.nixos.pc = { pkgs, ... }: {
    # Display manager
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    
    # Plasma 6 desktop
    services.desktopManager.plasma6.enable = true;
    
    # Required for some KDE apps
    programs.dconf.enable = true;
    
    # Enable KDE Connect
    programs.kdeconnect.enable = true;
    
    # X11 configuration for Plasma
    services.xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
    
    # KDE Packages
    environment.systemPackages = with pkgs; [
      # Core KDE apps
      kdePackages.kate
      kdePackages.kdenlive
      kdePackages.ark
      kdePackages.okular
      kdePackages.gwenview
      kdePackages.spectacle
      kdePackages.kcalc
      kdePackages.kcolorchooser
      kdePackages.partitionmanager
      
      # Additional KDE utilities
      kdePackages.filelight
      kdePackages.kdf
      krename  # Not in kdePackages
      
      # Theming
      kdePackages.breeze-gtk
      kdePackages.breeze-icons
      
      # System tools
      kdePackages.plasma-systemmonitor
      kdePackages.ksystemlog
      
      # KDE/Qt tools
      libsForQt5.qt5ct
      qt6ct
      libsForQt5.qtstyleplugin-kvantum
      
      # Additional apps that integrate well with Plasma
      kdePackages.yakuake  # Drop-down terminal
    ];
  };
}