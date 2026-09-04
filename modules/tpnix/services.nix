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
        # This chassis drives a 1920x1080 panel with a 24px i3bar; the shared
        # 2560x1440 default and the fontSize-derived bar height are wrong here.
        screenWidth = 1920;
        screenHeight = 1080;
        barHeight = 24;
        integrations = {
          xfsettingsd.enable = false;
        };
        powerProfiles = {
          allowSelection = false;
        };
      };

      # Power management configuration. No cpuFreqGovernor pin: ppd is forced on
      # above and its intel_pstate probe force-writes the governor at startup,
      # so a pin here never survives to boot. tpnix-power-profile below owns the
      # profile. See modules/hosts/common/services.nix.
      powerManagement = {
        resumeCommands = ''
          # Lock screen on resume via logind signal -> xss-lock (i3lock-stylix).
          # Guarded for the same set -e reason as the reassert below.
          ${pkgs.systemd}/bin/loginctl lock-sessions || echo "tpnix resume: loginctl lock-sessions failed" >&2
          # Re-assert the daemon profile after resume. Suppressed rather than
          # fatal: nixpkgs concatenates powerUpCommands after this in the same
          # set -e sleep-actions preStop script, so an unguarded failure here
          # would skip it. The journal line keeps the failure visible.
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance || echo "tpnix resume: powerprofilesctl set performance failed" >&2
        '';
      };

      systemd.services.tpnix-power-profile = import ../hosts/common/_power-profile-unit.nix pkgs;

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
