{ config, ... }:
{
  configurations.nixos.tec.module =
    { pkgs, lib, ... }:
    {
      # Enable printing
      services.printing = {
        enable = lib.mkDefault true;
        drivers = with pkgs; [
          gutenprint
          # hplip  # Requires unfree license
          brlaser
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

      # Enable fstrim for SSD optimization
      services.fstrim.enable = true;

      # Enable thermald for thermal management
      services.thermald.enable = true;
    };
}
