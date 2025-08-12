
# Service configurations for System76
{ config, ... }:
{
  configurations.nixos.system76.module = { pkgs, lib, ... }: {
    # Enable printing
    services.printing = {
      enable = lib.mkDefault true;
      drivers = with pkgs; [
        gutenprint
        hplip
        brlaser
        samsung-unified-linux-driver
      ];
    };
    
    # Enable CUPS for printing
    services.avahi = {
      enable = lib.mkDefault true;
      nssmdns4 = true;
      openFirewall = true;
    };
    
    # Power management
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
    
    # Enable GVFS for trash support, mounting, etc.
    services.gvfs.enable = true;
    
    # Enable thumbnail generation
    services.tumbler.enable = true;
    
    # Enable locate service
    services.locate = {
      enable = true;
      package = pkgs.plocate;
    };
  };
}