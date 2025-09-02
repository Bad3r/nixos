_: {
  configurations.nixos.tec.module =
    { pkgs, lib, ... }:
    {
      services = {
        # Enable printing
        printing = {
          enable = lib.mkDefault true;
          drivers = with pkgs; [
            gutenprint
            # hplip  # Requires unfree license
            brlaser
          ];
        };

        # Enable CUPS for printing
        avahi = {
          enable = lib.mkDefault true;
          nssmdns4 = true;
          openFirewall = true;
        };

        # Power management
        upower.enable = true;
        power-profiles-daemon.enable = true;

        # Enable GVFS for trash support, mounting, etc.
        gvfs.enable = true;

        # Enable thumbnail generation
        tumbler.enable = true;

        # Enable locate service
        locate = {
          enable = true;
          package = pkgs.plocate;
        };

        # Enable fstrim for SSD optimization
        fstrim.enable = true;

        # Enable thermald for thermal management
        thermald.enable = true;
      };
    };
}
