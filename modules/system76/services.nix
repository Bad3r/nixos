_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      services = {
        # Disable samples and network clients until configured on this host
        cloudflared.enable = lib.mkForce false;
        cloudflare-warp.enable = lib.mkForce false;

        # Disable printing by default on this host; remove Samsung driver
        printing = {
          enable = lib.mkForce false;
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

        # Enable weekly fstrim for SSDs
        fstrim.enable = true;

        # Thermal management (CPU/platform)
        thermald.enable = true;
      };

      # Disable ACME sample certs until configured with real domain/token
      security.acme = {
        acceptTerms = lib.mkDefault false;
        certs = lib.mkForce { };
      };
    };
}
