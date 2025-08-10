{ config, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {  # Desktop environment is a PC feature
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    
    services.desktopManager.plasma6.enable = true;
    programs.dconf.enable = true;
    
    # Enable KDE Connect
    programs.kdeconnect.enable = true;
    
    # XDG portal for KDE
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
    };
    
    # X11 configuration for Plasma compatibility
    services.xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };
}