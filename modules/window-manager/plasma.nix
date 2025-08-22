{ config, lib, ... }:
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
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

      # XDG portal for KDE
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
      };

      # KDE Packages
      environment.systemPackages = with pkgs; [
        # Core KDE apps
        kdePackages.kate # Text editor
        kdePackages.kdenlive # Video editor
        kdePackages.ark # Archive manager
        kdePackages.okular # Document viewer
        kdePackages.gwenview # Image viewer
        kdePackages.spectacle # Screenshot tool
        kdePackages.kcalc # Calculator
        kdePackages.kcolorchooser # Color picker
        kdePackages.partitionmanager # Disk management
        kdePackages.kdeconnect-kde # Phone integration

        # Additional KDE utilities
        kdePackages.filelight # Disk usage analyzer
        kdePackages.kdf # Disk free utility
        kdePackages.kcharselect # Character selector
        kdePackages.kfind # File search
        kdePackages.kruler # Screen ruler
        kdePackages.kwalletmanager # Wallet management
        kdePackages.ktimer # Timer
        kdePackages.sweeper # System cleaner
        krename # Batch file renamer (not in kdePackages)

        # Theming
        kdePackages.breeze-gtk
        kdePackages.breeze-icons

        # System tools
        kdePackages.plasma-systemmonitor
        kdePackages.ksystemlog

        # Additional apps that integrate well with Plasma
        kdePackages.yakuake # Drop-down terminal
      ];
    };
}
