{ lib, config, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    # Note: Individual application configurations are in home-manager modules
    # This module provides system-level PC applications
    # PC applications
    environment.systemPackages = with pkgs; lib.mkDefault [
      # Web browsers
      firefox
      chromium
      qutebrowser
      tor-browser
      
      # Media players
      mpv
      vlc
      
      # Terminal emulators
      kitty
      alacritty
      wezterm
      
      # File managers
      dolphin
      pcmanfm
      
      # Image viewers
      gwenview
      feh
      
      # PDF viewers
      okular
      evince
      
      # Text editors
      kate
      gedit
      
      # Archive managers
      ark
      file-roller
      
      # System utilities
      ksystemlog
      kcalc
      
      # Communication
      element-desktop
      signal-desktop
      telegram-desktop
      
      # Office
      libreoffice
      
      # Graphics
      gimp
      inkscape
      krita
      
      # Screenshots
      spectacle
      flameshot
      
      # Clipboard managers
      copyq
      
      # Password managers
      keepassxc
      bitwarden
    ];
  };
}