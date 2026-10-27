{ config, secretsRoot, ... }:
let
  inherit (config.flake.lib.nixos) _firewallLocalNetworkCidrs;
  sambaSecretFile = secretsRoot + "/songbird.yaml";
  sambaSecretExists = builtins.pathExists sambaSecretFile;
  songbirdSopsRuntimeReady = config.flake.lib.nixos.hosts.songbird.sopsRuntimeReady;
  # The LAN CIDRs firewallLocalTcpPortRanges admits, applied at the Samba layer
  # because openFirewall opens 139/445 on every interface. hosts deny = ALL also
  # closes the IPv6 path, matching that IPv4-only scoping.
  sambaHostsAllow = [
    "127.0.0.1"
    "::1"
  ]
  ++ config.flake.lib.nixos._firewallLocalNetworkCidrs;
  meshRange = config.flake.lib.nixos._cloudflareWarpMeshRange;
  # Both halves, as every other secret consumer here gates: the file arriving
  # before the age identity would activate sops.secrets with no key to decrypt
  # and fail sops-nix.service mid-switch.
  sambaSecretsReady = songbirdSopsRuntimeReady && sambaSecretExists;
  sambaMediaPathSecret = "songbird/samba-media-path";
  sambaMediaShareTemplate = "songbird/samba-media-share.conf";
in
{
  configurations.nixos.songbird.module =
    {
      config,
      options,
      pkgs,
      lib,
      metaOwner,
      ...
    }:
    let
      sambaMediaShareTemplatePath = config.sops.templates.${sambaMediaShareTemplate}.path;
      powerProfile = import ../common/_power-profile-unit.nix pkgs;

      llamaCommon = {
        n-gpu-layers = "all";
        cache-type-k = "q8_0";
        cache-type-v = "q8_0";
        # One slot gets the whole context, so the clients compact within ctx-size.
        parallel = 1;
        sleep-idle-seconds = 1800;
        dedup-cache-models = true;
      };
      llamaVision = llamaCommon // {
        mmproj-auto = true;
      };
      llamaMinicpm2b = llamaCommon // {
        hf-repo = "openbmb/MiniCPM5-2B-GGUF:Q8_0";
        ctx-size = 131072;
      };
      # llama-server models preset: one section per model, named as clients request it.
      # n-gpu-layers = all makes a model that does not fit in VRAM fail to load instead of offloading.
      llamaModels = {
        # Gemma 4 vision caps an image at ubatch-size tokens, and the 26B has no VRAM for more than the default 512.
        gemma-4-26b-a4b = llamaVision // {
          hf-repo = "unsloth/gemma-4-26B-A4B-it-GGUF:UD-IQ3_S";
          ctx-size = 128000;
          load-on-startup = true;
        };
        minicpm5-2b = llamaMinicpm2b;
        minicpm5-2b-dspark = llamaMinicpm2b // {
          spec-draft-hf = "magnitudedev/MiniCPM5-2B-DSpark-GGUF:DSpark";
          spec-type = "draft-dspark";
        };
        # Its chat template rejects system messages after the first, which agent clients commonly send.
        "qwen3.8-27b-gsq-mtp" = llamaVision // {
          # The IQ3_XXS file carries the MTP head; the tag names it in full, as `:IQ3_XXS` resolves to it anyway.
          hf-repo = "ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF:IQ3_XXS-mtp";
          ctx-size = 65536;
          spec-type = "draft-mtp";
        };
        # The only DFlash drafter for it is the Qwen3.5-9B one, whose GGUF llama.cpp 0.7.0 rejects.
        "mimo-v2.6-9b" = llamaVision // {
          hf-repo = "ggml-org/MiMo-V2.6-Distill-Qwen-9B-GGUF:Q8_0";
          ctx-size = 128000;
        };
        "lfm2.5-24b-a2b" = llamaCommon // {
          hf-repo = "unsloth/LFM2.5-24B-A2B-GGUF:UD-Q3_K_XL";
          ctx-size = 131072;
        };
      };
      # The default model clients request.
      llamaModel = "gemma-4-26b-a4b";
      llamaPort = 10100;
      paperlessRoot = "/data/paperless";
      llamaPreset = (pkgs.formats.iniWithGlobalSection { }).generate "llama-cpp-models.ini" {
        globalSection.version = 1;
        sections = llamaModels // {
          # [*] reaches every keyless child but not the router, which strips child CORS
          # headers; the default reflects any Origin, so any web page could read a child.
          "*".cors-origins = "http://127.0.0.1:${toString llamaPort}";
        };
      };
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
        ++ [
          {
            # Declared only while the r2-flake modules are imported.
            config = lib.optionalAttrs (options.services ? r2-restic) (
              lib.mkIf config.services.paperless.enable {
                services.r2-restic.paths = [ config.services.paperless.exporter.directory ];
                # A late or persistent backup run waits for an export in progress.
                systemd.services.r2-restic-backup.after = [ "paperless-exporter.service" ];
              }
            );
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
        # together. smbd/nmbd/winbindd are wantedBy and partOf samba.target
        # upstream, so detaching the target keeps them down at boot and the
        # target's stop still propagates to them; samba-wsdd ships
        # wantedBy = [ "multi-user.target" ] with no relation to the target at
        # all, so without its own rebind it advertised this host over
        # WS-Discovery at every boot with no share behind it.
        targets.samba.wantedBy = lib.mkForce [ ];
        services = {
          samba-wsdd = {
            wantedBy = lib.mkForce [ "samba.target" ];
            partOf = [ "samba.target" ];
          };

          # Force the power-profiles-daemon profile to performance at boot.
          songbird-power-profile = powerProfile.unit;

          paperless-web = lib.mkIf config.services.paperless.enable {
            serviceConfig.IPAddressAllow =
              _firewallLocalNetworkCidrs
              ++ lib.optional config.programs.cloudflare-warp.extended.enable meshRange;
          };
          # tmpfiles refuses a hop from the vx-owned /data into a foreign-owned child, and its
          # implicit parent creation would leave paperlessRoot root-owned.
          paperless-secret-key = lib.mkIf config.services.paperless.enable {
            serviceConfig.ExecStartPre = lib.mkBefore [
              "+${config.systemd.package}/bin/systemd-tmpfiles --create ${pkgs.writeText "paperless-root.conf" "d '${paperlessRoot}' 0755 ${metaOwner.username} users - -"}"
            ];
          };
          # The owner drops scans into the inbox; the default ACL lets paperless read them under any umask.
          paperless-consumer = lib.mkIf config.services.paperless.enable {
            serviceConfig.ExecStartPre = "+${lib.getExe' pkgs.acl "setfacl"} -m u:${metaOwner.username}:rwx,d:u:${metaOwner.username}:rwx,d:u:${config.services.paperless.user}:rwx ${config.services.paperless.consumptionDir}";
          };
          # Copies keep the media files' 0600 mode, and r2-restic-backup reads them as the owner.
          paperless-exporter = lib.mkIf config.services.paperless.enable {
            serviceConfig.ExecStartPost = "+${lib.getExe' pkgs.acl "setfacl"} -R -m u:${metaOwner.username}:rX ${config.services.paperless.exporter.directory}";
          };
        };
        # Runs a 23:00 export missed while the host was off at the next boot.
        timers.paperless-exporter = lib.mkIf config.services.paperless.enable {
          timerConfig.Persistent = true;
        };
      };

      # lock = logind Lock signal -> systemd-lock-handler -> lock.target (i3lock).
      # Desktop chassis: no lid switch to handle.
      services.logind.settings.Login.HandlePowerKey = "lock";

      programs.llama-cpp.extended = {
        # Only for the RTX 5080 (sm_120), the host's one GPU.
        package = pkgs.llama-cpp-cuda.override {
          llama-cpp = pkgs.llama-cpp.override {
            cudaPackages = pkgs.cudaPackages.override {
              config = pkgs.config // {
                cudaCapabilities = [ "12.0" ];
              };
            };
          };
        };

        client = {
          model = llamaModel;
          # Headroom for a large tool result that lands after the clients' last compaction check.
          models = lib.mapAttrs (_: preset: preset.ctx-size - 8192) llamaModels;
        };
      };

      services = {
        cloudflared.enable = true;

        # dataDir and PostgreSQL stay on the root disk; documents go to /data.
        paperless = {
          address = "0.0.0.0";
          mediaDir = "${paperlessRoot}/media";
          consumptionDir = "${paperlessRoot}/consume";
          exporter = {
            directory = "${paperlessRoot}/export";
            # Clear of r2-restic-backup's 00:00 to 01:00 window.
            onCalendar = "23:00:00";
          };
        };

        # Router mode: no model on the command line, one loaded model at a time.
        llama-cpp.settings = {
          # Without an API key the server stays on loopback.
          host = if config.services.llama-cpp.apiKeyFile != null then "0.0.0.0" else "127.0.0.1";
          port = llamaPort;
          models-preset = "${llamaPreset}";
          models-max = 1;
        };

        samba = {
          enable = true;
          openFirewall = true;
          settings = {
            global = {
              "map to guest" = "Bad User";
              "server min protocol" = "SMB3";
              "hosts deny" = "ALL";
              "hosts allow" = lib.concatStringsSep " " (
                sambaHostsAllow ++ lib.optional config.programs.cloudflare-warp.extended.enable meshRange
              );
            };
          };
        };

        samba-wsdd = {
          enable = true;
          openFirewall = true;
        };

        # A non-empty settings makes /etc/lact/config.yaml a store symlink, so
        # lactd cannot save GUI changes; they last only until it restarts.
        lact.settings = {
          version = 7;
          daemon = {
            log_level = "info";
            admin_group = "wheel";
            disable_clocks_cleanup = false;
          };
          apply_settings_timer = 5;
          gpus."10DE:2C02-1043:8A47-0000:02:00.0" = {
            fan_control_enabled = false;
            power_mizer_mode = "PreferMaximumPerformance";
            power_cap = 450.0;
            voltage_boost = 100;
          };
          current_profile = null;
          auto_switch_profiles = false;
        };

        # intel_pstate on the 285K exposes the energy-performance preference
        # that power-profiles-daemon drives; the shared i3 launcher shells out
        # to powerprofilesctl.
        power-profiles-daemon.enable = true;

        # Desktop K-SKU under a 360 mm AIO with BIOS Q-Fan curves: thermald has
        # no platform to manage here.
        thermald.enable = false;
      };

      # No cpuFreqGovernor pin here: ppd's intel_pstate probe force-writes
      # scaling_governor = powersave for every EPP-capable CPU at startup, so a
      # static pin only survives until the daemon comes up.
      # songbird-power-profile drives the EPP instead.
      powerManagement = {
        resumeCommands = ''
          # Lock screen on resume via logind Lock signal -> lock.target (i3lock).
          # Guarded for the same set -e reason as the reassert below.
          ${pkgs.systemd}/bin/loginctl lock-sessions || echo "songbird resume: loginctl lock-sessions failed" >&2
          # Re-assert the daemon profile after resume. Suppressed rather than
          # fatal: nixpkgs concatenates powerUpCommands after this in the same
          # set -e sleep-actions preStop script, so an unguarded failure here
          # would skip it. The journal line keeps the failure visible.
          ${powerProfile.command} || echo "songbird resume: powerprofilesctl set performance failed" >&2
        '';
      };

      # CoolerControl stays disabled via the shared baseline: every fan and the
      # AIO pump run from plain PWM headers under BIOS Q-Fan by design
      # (docs/hosts/songbird/songbird-hardware.md), so no OS-side fan software exists
      # or is needed.
    };
}
