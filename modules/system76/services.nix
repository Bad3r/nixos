_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      # Cannot use systemd.sysusers with normal users (only supports system users)
      # systemd.sysusers.enable = true;
      systemd.coredump = {
        enable = true;
        extraConfig = ''
          MaxUse=1G
          KeepFree=2G
          MaxRetentionSec=3d
        '';
      };

      # NOTE: Battery charge thresholds (system76-power charge-thresholds) are NOT supported
      # on Darter Pro 6 firmware. This requires newer System76 firmware with EC threshold support.
      # Laptops that support it: Pangolin, some newer Darter/Galago models with updated firmware.

      # Ignore power button to prevent accidental shutdowns
      # Lid switch uses default "suspend" - xss-lock with --transfer-sleep-lock
      # ensures screen locks before suspend completes
      services.logind.settings = {
        Login.HandlePowerKey = "ignore";
      };

      services = {
        journald = {
          storage = "persistent";
          extraConfig = ''
            SystemMaxUse=1G
            SystemKeepFree=10G
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
        # power-profiles-daemon conflicts with thermald; keep disabled
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
        # Uses Intel thermald instead of system76-power for thermal throttling
        # NOTE: System76 EC over-reports temps by ~5°C causing premature shutdowns
        # Config and TCC offset (below) compensate for inflated readings
        thermald = {
          enable = true;
          debug = true;
          configFile = ./thermald.conf.xml;
        };

        # System76 process scheduler for improved desktop responsiveness
        # Adjusts CFS latency on AC/battery and boosts foreground processes
        system76-scheduler.enable = true;

        # LACT: GPU control and monitoring (power limits, fan curves, clocks)
        # Supports NVIDIA, AMD, and Intel GPUs
        lact.enable = true;
      };

      # CPU governor: performance mode by default
      powerManagement.cpuFreqGovernor = "performance";

      # Set TCC (Thermal Control Circuit) offset to 0
      # Allows CPU to run up to Tjmax (100°C) before hardware throttling
      # Required because System76 EC over-reports temperatures by ~5°C
      systemd.tmpfiles.rules = [
        "w /sys/class/thermal/cooling_device13/cur_state - - - - 0"
      ];

      # CoolerControl: DISABLED - conflicts with System76 EC fan control
      # When both CoolerControl and EC control fans simultaneously (e.g., Fn+1),
      # the EC hangs causing system crash. See: github.com/pop-os/system76-dkms/issues/11
      # Let EC handle fans natively; thermald handles CPU thermal throttling.
      programs.coolercontrol.enable = false;

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
