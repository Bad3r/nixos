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

      # lock = logind signal -> xss-lock --transfer-sleep-lock (i3lock-stylix)
      services.logind.settings.Login = {
        HandlePowerKey = "lock";
        HandleLidSwitch = "lock"; # ignore, lock, suspend, poweroff, hibernate
        HandleLidSwitchExternalPower = "lock"; # On AC power
        HandleLidSwitchDocked = "lock"; # External display connected
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
        # power-profiles-daemon conflicts with system76-power; keep disabled
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

        # Thermal management handled by system76-power (hardware.system76.power-daemon)
        # thermald disabled - system76-power provides thermal management, power profiles,
        # and battery charge thresholds via EC
        thermald.enable = false;

        # System76 process scheduler for improved desktop responsiveness
        # Adjusts CFS latency on AC/battery and boosts foreground processes
        system76-scheduler.enable = true;

        # LACT: GPU control and monitoring (power limits, fan curves, clocks)
        # Supports NVIDIA, AMD, and Intel GPUs
        lact.enable = true;
      };

      # Power management configuration
      # - powerManagement: kernel-level CPU governor and suspend/resume hooks
      # - system76-power: System76 daemon for fans, backlight, turbo policies
      powerManagement = {
        enable = true;
        cpuFreqGovernor = "performance"; # ondemand, powersave, performance
        powertop.enable = false; # Aggressive USB autosuspend causes device issues
        resumeCommands = ''
          # Lock screen on resume via logind signal -> xss-lock (i3lock-stylix)
          ${pkgs.systemd}/bin/loginctl lock-sessions
        '';
      };

      # Set system76-power profile to performance on boot
      # Note: system76-power may report non-critical errors (e.g., SATA link PM not supported)
      # but still successfully set the profile
      systemd.services.system76-power-profile = {
        description = "Set System76 power profile to performance";
        wantedBy = [ "multi-user.target" ];
        after = [ "com.system76.PowerDaemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.system76-power}/bin/system76-power profile performance";
          RemainAfterExit = true;
          # Allow exit code 1 (non-critical errors like unsupported SATA link PM)
          SuccessExitStatus = [ 1 ];
        };
      };

      # CoolerControl: DISABLED - conflicts with System76 EC fan control
      # When both CoolerControl and EC control fans simultaneously (e.g., Fn+1),
      # the EC hangs causing system crash. See: github.com/pop-os/system76-dkms/issues/11
      # Let EC and system76-power handle fans natively.
      programs.coolercontrol.enable = false;

      # Disable ACME sample certs until configured with real domain/token
      security.acme = {
        acceptTerms = lib.mkDefault false;
        certs = lib.mkForce { };
      };
    };
}
