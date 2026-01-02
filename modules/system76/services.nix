_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      # Cannot use systemd.sysusers with normal users (only supports system users)
      # systemd.sysusers.enable = true;
      systemd.coredump.enable = true;

      # NOTE: Battery charge thresholds (system76-power charge-thresholds) are NOT supported
      # on Darter Pro 6 firmware. This requires newer System76 firmware with EC threshold support.
      # Laptops that support it: Pangolin, some newer Darter/Galago models with updated firmware.

      # Ignore power button to prevent accidental shutdowns
      services.logind.settings = {
        Login.HandlePowerKey = "ignore";
      };

      services = {
        journald = {
          storage = "persistent";
          extraConfig = ''
            SystemMaxUse=1G
            SystemKeepFree=10%
          '';
        };

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

        # System76 process scheduler for improved desktop responsiveness
        # Adjusts CFS latency on AC/battery and boosts foreground processes
        system76-scheduler.enable = true;

        # LACT: GPU control and monitoring (power limits, fan curves, clocks)
        # Supports NVIDIA, AMD, and Intel GPUs
        lact.enable = true;
      };

      # CoolerControl: System-wide fan curve management
      # Uses hwmon sensors and liquidctl for comprehensive cooling control
      programs.coolercontrol.enable = true;

      # Set system76-power to performance profile by default on boot
      # Uses a separate oneshot service to avoid race condition with D-Bus registration
      systemd.services.system76-power-profile = {
        description = "Set System76 Power Profile";
        after = [ "system76-power.service" ];
        requires = [ "system76-power.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "set-system76-power-profile" ''
            # Wait for D-Bus service to be available (up to 10 seconds)
            for i in $(seq 1 20); do
              if ${pkgs.system76-power}/bin/system76-power profile performance 2>/dev/null; then
                exit 0
              fi
              sleep 0.5
            done
            echo "Failed to set power profile after 10 seconds" >&2
            exit 1
          '';
        };
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
