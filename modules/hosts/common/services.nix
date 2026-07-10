{
  flake.nixosModules.hosts-common.imports = [
    (
      { lib, pkgs, ... }:
      {
        # Cannot use systemd.sysusers with normal users (only supports system users)
        # systemd.sysusers.enable = true;
        systemd.coredump = {
          enable = true;
          settings.Coredump = {
            MaxUse = "1G";
            KeepFree = "2G";
          };
        };

        services = {
          journald = {
            storage = "persistent";
            extraConfig = ''
              SystemMaxUse=1G
              SystemKeepFree=10G
            '';
          };

          avahi = {
            enable = lib.mkDefault true;
            nssmdns4 = true;
            openFirewall = true;
          };

          # Power management
          upower.enable = true;

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
        };

        # Kernel-level CPU governor and suspend/resume hooks; each host sets
        # cpuFreqGovernor and resumeCommands next to its power stack.
        powerManagement = {
          enable = true;
          powertop.enable = false; # Aggressive USB autosuspend causes device issues
        };

        # Keep hardware fan-control tooling disabled unless a host needs manual tuning.
        programs.coolercontrol.enable = false;

        # Disable ACME sample certs until configured with real domain/token
        security.acme = {
          acceptTerms = lib.mkDefault false;
          certs = lib.mkForce { };
        };
      }
    )
  ];
}
