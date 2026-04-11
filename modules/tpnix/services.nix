_: {
  configurations.nixos.tpnix.module =
    { pkgs, lib, ... }:
    {
      # Cannot use systemd.sysusers with normal users (only supports system users)
      # systemd.sysusers.enable = true;
      systemd.coredump = {
        enable = true;
        extraConfig = ''
          MaxUse=1G
          KeepFree=2G
        '';
      };

      # lock = logind signal -> xss-lock --transfer-sleep-lock (i3lock-stylix)
      services.logind.settings.Login = {
        HandlePowerKey = lib.mkDefault "lock";
        HandleLidSwitch = lib.mkDefault "suspend"; # ignore, lock, suspend, poweroff, hibernate
        HandleLidSwitchExternalPower = lib.mkDefault "suspend"; # On AC power
        HandleLidSwitchDocked = lib.mkDefault "suspend"; # External display connected
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
        power-profiles-daemon.enable = lib.mkForce true;

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

        thermald.enable = lib.mkDefault true;
      };

      # Power management configuration.
      powerManagement = {
        enable = true;
        cpuFreqGovernor = lib.mkForce "performance"; # ondemand, powersave, performance
        powertop.enable = false; # Aggressive USB autosuspend causes device issues
        resumeCommands = ''
          # Lock screen on resume via logind signal -> xss-lock (i3lock-stylix)
          ${pkgs.systemd}/bin/loginctl lock-sessions

          # Re-assert the daemon profile after resume.
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
        '';
      };

      systemd.services.tpnix-power-profile = {
        description = "Force power-profiles-daemon profile to performance";
        wantedBy = [ "multi-user.target" ];
        wants = [ "power-profiles-daemon.service" ];
        after = [ "power-profiles-daemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
          RemainAfterExit = true;
        };
      };

      # Keep hardware fan-control tooling disabled unless this host needs manual tuning.
      programs.coolercontrol.enable = false;

      # Disable ACME sample certs until configured with real domain/token
      security.acme = {
        acceptTerms = lib.mkDefault false;
        certs = lib.mkForce { };
      };
    };
}
