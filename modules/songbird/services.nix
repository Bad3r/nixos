{ config, secretsRoot, ... }:
let
  sambaSecretFile = secretsRoot + "/songbird.yaml";
  sambaSecretExists = builtins.pathExists sambaSecretFile;
  # Both halves, as every other secret consumer here gates: the file arriving
  # before the age identity would activate sops.secrets with no key to decrypt
  # and fail sops-nix.service mid-switch.
  sambaSecretsReady = config.flake.lib.nixos.hosts.songbird.sopsRuntimeReady && sambaSecretExists;
  sambaMediaPathSecret = "songbird/samba-media-path";
  sambaMediaShareTemplate = "songbird/samba-media-share.conf";
in
{
  configurations.nixos.songbird.module =
    {
      config,
      pkgs,
      lib,
      metaOwner,
      ...
    }:
    let
      sambaMediaShareTemplatePath = config.sops.templates.${sambaMediaShareTemplate}.path;
    in
    {
      imports =
        lib.optionals sambaSecretsReady [
          {
            services.samba.settings.media.include = sambaMediaShareTemplatePath;

            sops.secrets.${sambaMediaPathSecret} = {
              sopsFile = sambaSecretFile;
              key = "samba_media_path";
              owner = "root";
              group = "root";
              mode = "0400";
            };

            sops.templates.${sambaMediaShareTemplate} = {
              content = ''
                path = ${config.sops.placeholder.${sambaMediaPathSecret}}
                browsable = yes
                read only = yes
                guest ok = yes
                force user = ${metaOwner.username}
              '';
              owner = "root";
              group = "root";
              mode = "0400";
              reloadUnits = [
                "samba-smbd.service"
                "samba-nmbd.service"
              ];
            };
          }
        ]
        ++ lib.optionals (!sambaSecretsReady) [
          {
            warnings = [
              (
                if sambaSecretExists then
                  "songbird Samba media share skipped because flake.lib.nixos.hosts.songbird.sopsRuntimeReady is false."
                else
                  "songbird Samba media share skipped because ${toString sambaSecretFile} is missing."
              )
            ];
          }
        ];

      systemd = {
        # Local crash-triage retention on top of the shared coredump baseline.
        coredump.settings.Coredump.MaxRetentionSec = "3d";

        # On-demand Samba: keep units available but don't auto-start at boot.
        # Start manually with `systemctl start samba.target` when sharing is
        # needed; `systemctl stop samba.target` brings down smbd/nmbd/wsdd
        # together. smbd/nmbd/winbindd are wantedBy samba.target upstream, so
        # detaching the target is enough for them; samba-wsdd ships
        # wantedBy = [ "multi-user.target" ] with no relation to the target at
        # all, so without its own rebind it advertised this host over
        # WS-Discovery at every boot with no share behind it.
        targets.samba.wantedBy = lib.mkForce [ ];
        services.samba-wsdd = {
          wantedBy = lib.mkForce [ "samba.target" ];
          partOf = [ "samba.target" ];
        };

        # Force the power-profiles-daemon profile to performance at boot: the
        # desktop counterpart of system76-power-profile on system76, where the
        # System76 EC daemon owns the profile instead.
        services.songbird-power-profile = {
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
      };

      # lock = logind signal -> xss-lock --transfer-sleep-lock (i3lock-stylix).
      # Desktop chassis: no lid switch to handle.
      services.logind.settings.Login.HandlePowerKey = "lock";

      services = {
        cloudflared.enable = true;

        cloudflare-warp = {
          enable = true;
          package = pkgs.cloudflare-warp.override { headless = true; };
        };

        # No drivers list: nixpkgs reads services.printing.drivers only inside
        # its own mkIf cfg.enable, so alongside a forced-off enable it named
        # packages nothing installs, and it was a laptop-era set copied from
        # system76 rather than anything this desktop justified.
        printing.enable = lib.mkForce false;

        samba = {
          enable = true;
          openFirewall = true;
          settings = {
            global = {
              "map to guest" = "Bad User";
              "server min protocol" = "SMB3";
            };
          };
        };

        samba-wsdd = {
          enable = true;
          openFirewall = true;
        };

        # intel_pstate on the 285K exposes the energy-performance preference
        # that power-profiles-daemon drives; the shared i3 launcher keeps its
        # default powerprofilesctl backend (gui.i3.powerProfiles.backend).
        # This replaces the system76-power stack of the System76 chassis.
        power-profiles-daemon.enable = true;

        # Desktop K-SKU under a 360 mm AIO with BIOS Q-Fan curves: thermald has
        # no platform to manage here.
        thermald.enable = false;

        # System76 process scheduler for improved desktop responsiveness
        # (hardware-agnostic: CFS latency tuning and foreground boosts).
        system76-scheduler.enable = true;

        # LACT: GPU control and monitoring (power limits, fan curves, clocks)
        # over NVML for the RTX 5080.
        lact.enable = true;
      };

      # No cpuFreqGovernor pin here, unlike system76, which forces
      # power-profiles-daemon off and so owns the governor itself: ppd's
      # intel_pstate probe force-writes scaling_governor = powersave for every
      # EPP-capable CPU at startup, so a static pin only survives until the
      # daemon comes up. songbird-power-profile drives the EPP instead.
      powerManagement = {
        resumeCommands = ''
          # Lock screen on resume via logind signal -> xss-lock (i3lock-stylix).
          # Guarded for the same set -e reason as the reassert below.
          ${pkgs.systemd}/bin/loginctl lock-sessions || echo "songbird resume: loginctl lock-sessions failed" >&2
          # Re-assert the daemon profile after resume. Suppressed rather than
          # fatal: nixpkgs concatenates powerUpCommands after this in the same
          # set -e sleep-actions preStop script, so an unguarded failure here
          # would skip it. The journal line keeps the failure visible.
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance || echo "songbird resume: powerprofilesctl set performance failed" >&2
        '';
      };

      # CoolerControl stays disabled via the shared baseline: every fan and the
      # AIO pump run from plain PWM headers under BIOS Q-Fan by design
      # (docs/songbird/project-songbird.md), so no OS-side fan software exists
      # or is needed.
    };
}
