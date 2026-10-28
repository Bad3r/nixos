/*
  Module: nvidia-gpu
  Description: Parameterized NVIDIA GPU wiring shared by all hosts with an
  NVIDIA card. Hosts pick the driver branch, kernel-module flavor, VA-API
  routing, and display mode instead of restating the full stack.
*/
_:
let
  NvidiaGpuModule =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.gpu.nvidia;
    in
    {
      options.gpu.nvidia = {
        enable = lib.mkEnableOption "shared NVIDIA GPU wiring";

        package = lib.mkOption {
          type = lib.types.package;
          default = config.boot.kernelPackages.nvidiaPackages.production;
          defaultText = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.production";
          description = ''
            NVIDIA driver package. Pick the branch matching the GPU generation
            (legacy_* for cards dropped from production, production/latest for
            current silicon; Blackwell requires 570+).
          '';
        };

        open = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Use the open NVIDIA kernel modules. Required on Blackwell and newer
            (the proprietary modules do not support them); keep false on
            pre-Turing cards, which the open modules do not support.
          '';
        };

        containerToolkit.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable nvidia-container-toolkit for GPU passthrough into containers.";
        };

        metamode = lib.mkOption {
          type = lib.types.str;
          default = "nvidia-auto-select";
          example = "2560x1440_144";
          description = ''
            Mode token for the X screen metamode. "nvidia-auto-select" takes the
            EDID-preferred mode, which on many high-refresh panels is 60 Hz;
            name a `<width>x<height>_<rate>` mode to pin the rate instead. The
            X screen mode is also what RandR falls back to when the driver
            re-detects the display, so a wrong value here silently returns after
            every hotplug or DPMS wake.

            With "nvidia-auto-select", the i3 display-hotplug handler selects
            the highest advertised refresh rate at the preferred resolution on
            session startup and reconnect. If no preferred mode is advertised,
            it uses the largest advertised resolution. A pinned mode overrides
            this selection. Other formats emit an evaluation warning and use
            automatic selection. A rejected MetaMode assignment falls back to
            xrandr, and failed xrandr mode requests are logged and fall back to
            RandR's preferred mode with `--auto`.

            A pinned mode names an EDID the attached panel may not advertise.
            That does not cost a session: the driver discards MetaModes it
            cannot validate and "nvidia-auto-select" is guaranteed present, so X
            still starts. Every configured mode carries
            `AllowGSYNCCompatible=On`; RandR-created modes drop it, so the i3
            display-hotplug handler sets modes through one CurrentMetaMode
            assignment that carries it.
          '';
        };

        vaapi.backend = lib.mkOption {
          type = lib.types.enum [
            "nvidia"
            "intel-media"
          ];
          default = "nvidia";
          description = ''
            VA-API decode path. "nvidia" installs nvidia-vaapi-driver (VA-API
            handed to NVDEC). "intel-media" routes decode to the Intel iGPU via
            intel-media-driver and suppresses nvidia-vaapi-driver; use it when
            the NVDEC handoff is unstable (Xid 31 MMU faults under decode-context
            churn) or when the iGPU should own decode.
          '';
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.xserver = {
              videoDrivers = lib.mkDefault [ "nvidia" ];
              # G-SYNC Compatible does not run under the full composition pipeline.
              screenSection =
                let
                  metaMode = m: "${m} +0+0 {AllowGSYNCCompatible=On}";
                  modes = [
                    cfg.metamode
                  ]
                  ++ lib.optional (cfg.metamode != "nvidia-auto-select") "nvidia-auto-select";
                in
                lib.mkDefault ''
                  Option "ForceFullCompositionPipeline" "false"
                  Option "metamodes" "${lib.concatMapStringsSep "; " metaMode modes}"
                '';
            };

            hardware = {
              graphics.extraPackages = [ pkgs.vulkan-validation-layers ];

              nvidia = {
                inherit (cfg) package open;
                modesetting.enable = lib.mkDefault true;
                powerManagement.enable = lib.mkDefault true;
                # Fine-grained power management (D3 power gating) only applies to
                # PRIME offload setups.
                powerManagement.finegrained = lib.mkDefault false;
              };

              # Containers: NVIDIA container toolkit for GPU passthrough
              nvidia-container-toolkit.enable = cfg.containerToolkit.enable;
            };

            # Diagnostics: vulkaninfo and glxinfo
            environment.systemPackages = with pkgs; [
              vulkan-tools
              mesa-demos
            ];
          }

          (lib.mkIf (cfg.vaapi.backend == "nvidia") {
            # VA-API handed to NVDEC: videoAcceleration is nixpkgs' knob that
            # installs nvidia-vaapi-driver into hardware.graphics.extraPackages.
            # Setting it here (rather than adding the package directly) avoids a
            # double-install, since it already defaults to true.
            hardware.nvidia.videoAcceleration = true;
          })

          (lib.mkIf (cfg.vaapi.backend == "intel-media") {
            # VA-API decode routes through Intel Quick Sync (iHD), not NVDEC.
            # Suppress nixpkgs' default nvidia-vaapi-driver install
            # (videoAcceleration defaults to true and is its only consumer).
            hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
            hardware.nvidia.videoAcceleration = false;
          })
        ]
      );
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "nvidia-kernel-modules"
    "nvidia-x11"
    "nvidia-settings"
  ];

  flake.nixosModules.nvidia-gpu = NvidiaGpuModule;
}
