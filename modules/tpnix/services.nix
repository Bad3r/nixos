_: {
  configurations.nixos.tpnix.module =
    { pkgs, lib, ... }:
    {
      # logind lid/power-key behavior lives in modules/tpnix/power.nix.
      services = {
        cloudflared.enable = lib.mkForce false;

        printing = {
          enable = true;
          drivers = with pkgs; [
            gutenprint
            hplip
            brlaser
          ];
        };

        power-profiles-daemon.enable = lib.mkForce true;

        thermald.enable = lib.mkDefault true;
      };

      gui.i3 = {
        integrations = {
          xfsettingsd.enable = false;
        };
        powerProfiles = {
          allowSelection = false;
        };
      };

      # Power management configuration.
      powerManagement = {
        cpuFreqGovernor = lib.mkForce "performance"; # ondemand, powersave, performance
        resumeCommands = ''
          # Lock screen on resume via logind signal -> xss-lock (i3lock-stylix)
          ${pkgs.systemd}/bin/loginctl lock-sessions

          # Re-assert the daemon profile after resume.
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
        '';
      };

      systemd.services.tpnix-power-profile = {
        description = "Force power-profiles-daemon profile to performance";
        wantedBy = [ "graphical.target" ];
        wants = [ "power-profiles-daemon.service" ];
        after = [ "power-profiles-daemon.service" ];
        startLimitBurst = 3;
        startLimitIntervalSec = 3600;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 3;
        };
      };

      # espanso's Wayland/X11 split is decided per host; this chassis runs X11.
      home-manager.sharedModules = lib.mkAfter [
        {
          services.espanso = {
            waylandSupport = lib.mkForce false;
            x11Support = lib.mkForce true;
          };
        }
      ];
    };
}
