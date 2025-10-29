_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      systemd.sysusers.enable = true;

      # Ignore power button to prevent accidental shutdowns
      services.logind.settings = {
        Login.HandlePowerKey = "ignore";
      };

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
        # Prefer system76-power (enabled via nixos-hardware + hardware.system76.enableAll)
        # Avoid conflicting governors/services on laptops
        power-profiles-daemon.enable = lib.mkForce false;

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

      xdg.mime.defaultApplications = {
        "inode/directory" = lib.mkForce "nemo.desktop";
        "application/x-directory" = lib.mkForce "nemo.desktop";
      };

      # Disable ACME sample certs until configured with real domain/token
      security.acme = {
        acceptTerms = lib.mkDefault false;
        certs = lib.mkForce { };
      };
    };
}
