_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      services = {
        # Disable samples and network clients until configured on this host
        cloudflared.enable = lib.mkForce false;
        cloudflare-warp.enable = lib.mkForce false;
        # Enable printing
        printing = {
          enable = lib.mkDefault true;
          drivers = with pkgs; [
            gutenprint
            # hplip  # Requires unfree license
            brlaser
            samsung-unified-linux-driver
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
      };

      # Disable ACME sample certs until configured with real domain/token
      security.acme = {
        acceptTerms = lib.mkDefault false;
        certs = lib.mkForce { };
      };
    };
}
