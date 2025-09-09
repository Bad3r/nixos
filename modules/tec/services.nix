_: {
  configurations.nixos.tec.module =
    { pkgs, lib, ... }:
    {
      # Temporary host-specific overrides: disable unconfigured services
      # - Cloudflared Tunnel sample (placeholder UUID)
      # - ACME Cloudflare DNS-01 sample (placeholder domain/token)
      # These samples are part of the shared workstation module; until
      # properly configured on this host, keep them disabled to avoid
      # failing systemd units during evaluation/build.
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

        # Ensure Cloudflared tunnel is disabled until configured
        cloudflared.enable = lib.mkForce false;

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

      # Disable ACME sample certs until configured
      security.acme = {
        acceptTerms = lib.mkDefault false;
        certs = lib.mkForce { };
      };
    };
}
