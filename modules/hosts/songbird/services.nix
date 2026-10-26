{ config, secretsRoot, ... }:
let
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
      llamaGemma12b = llamaVision // {
        hf-repo = "unsloth/gemma-4-12B-it-qat-GGUF:UD-Q4_K_XL";
        ctx-size = 128000;
        # An image must fit in one ubatch, so the default 512 caps Gemma 4's 1120 image tokens.
        # 2048 costs ~2.2 GiB more VRAM, which the 26B cannot spare.
        ubatch-size = 2048;
      };
      llamaQwen9b = llamaVision // {
        hf-repo = "unsloth/Qwen3.5-9B-MTP-GGUF:UD-Q5_K_XL";
        ctx-size = 128000;
      };
      llamaMinicpm2b = llamaCommon // {
        hf-repo = "openbmb/MiniCPM5-2B-GGUF:Q8_0";
        ctx-size = 131072;
      };
      # llama-server models preset: one section per model, named as clients request it.
      # n-gpu-layers = all makes a model that does not fit in VRAM fail to load instead of offloading.
      llamaModels = {
        gemma-4-12b-it-qat = llamaGemma12b // {
          load-on-startup = true;
        };
        gemma-4-12b-it-qat-mtp = llamaGemma12b // {
          spec-draft-hf = "magnitudedev/gemma-4-12B-it-qat-MTP-GGUF:Q4_0";
          spec-type = "draft-mtp";
        };
        "qwen3.5-9b" = llamaQwen9b;
        # Without a draft file, draft-mtp uses the model's own MTP layers.
        "qwen3.5-9b-mtp" = llamaQwen9b // {
          spec-type = "draft-mtp";
        };
        "qwen3.5-9b-dflash" = llamaQwen9b // {
          spec-draft-hf = "magnitudedev/Qwen3.5-9B-DFlash-GGUF:Q8_0";
          spec-type = "draft-dflash";
        };
        minicpm5-2b = llamaMinicpm2b;
        minicpm5-2b-dspark = llamaMinicpm2b // {
          spec-draft-hf = "magnitudedev/MiniCPM5-2B-DSpark-GGUF:DSpark";
          spec-type = "draft-dspark";
        };
        gemma-4-26b-a4b = llamaVision // {
          hf-repo = "unsloth/gemma-4-26B-A4B-it-GGUF:UD-IQ3_S";
          ctx-size = 128000;
        };
        "qwen3.8-27b" = llamaVision // {
          hf-repo = "unsloth/Qwen3.8-27B-GGUF:UD-IQ3_XXS";
          ctx-size = 65536;
        };
        "qwen3.6-35b-a3b" = llamaVision // {
          hf-repo = "unsloth/Qwen3.6-35B-A3B-GGUF:UD-IQ3_XXS";
          ctx-size = 65536;
          # Weights, KV, and projector do not all fit in 16 GiB, so the projector runs on the CPU.
          mmproj-offload = false;
        };
      };
      # The model `claude-local` and `codex -p local` request.
      llamaModel = "gemma-4-12b-it-qat";
      llamaPort = 10100;
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
        services.samba-wsdd = {
          wantedBy = lib.mkForce [ "samba.target" ];
          partOf = [ "samba.target" ];
        };

        # Force the power-profiles-daemon profile to performance at boot.
        services.songbird-power-profile = powerProfile.unit;
      };

      # lock = logind Lock signal -> systemd-lock-handler -> lock.target (i3lock).
      # Desktop chassis: no lid switch to handle.
      services.logind.settings.Login.HandlePowerKey = "lock";

      programs.llama-cpp.extended.client = {
        model = llamaModel;
        contextWindow = llamaModels.${llamaModel}.ctx-size;
      };

      services = {
        cloudflared.enable = true;

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
