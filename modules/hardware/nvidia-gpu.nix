/*
  Module: nvidia-gpu
  Description: Parameterized NVIDIA GPU wiring shared by all hosts with an
  NVIDIA card. Hosts pick the driver branch, kernel-module flavor, VA-API
  routing, and display topology instead of restating the full stack.

  Profiles:
    * Desktop (single GPU, e.g. Blackwell): set `package` to a current branch,
      `open = true`, leave `prime.enable = false`.
    * Laptop (hybrid graphics): set `prime.enable = true` with the chassis bus
      IDs so the iGPU drives the panel through PRIME sync.
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

        prime = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable PRIME sync so the iGPU drives the panel while NVIDIA renders (dual-GPU laptops).";
          };

          intelBusId = lib.mkOption {
            type = lib.types.str;
            default = "PCI:0:2:0";
            example = "PCI:0:2:0";
            description = ''
              PCI address for the Intel iGPU when PRIME sync is enabled. Determine via
              `lspci -nn | grep VGA` if the default does not match this chassis.
            '';
          };

          nvidiaBusId = lib.mkOption {
            type = lib.types.str;
            default = "PCI:1:0:0";
            example = "PCI:1:0:0";
            description = ''
              PCI address for the NVIDIA dGPU when PRIME sync is enabled. Override if
              `lspci -nn | grep NVIDIA` reports a different slot.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.xserver = {
              videoDrivers = lib.mkDefault [ "nvidia" ];
              # Tear-free: Force full composition pipeline for NVIDIA
              screenSection = lib.mkDefault ''
                Option "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
              '';
            };

            hardware = {
              graphics.extraPackages = [ pkgs.vulkan-validation-layers ];

              nvidia = {
                inherit (cfg) package open;
                modesetting.enable = lib.mkDefault true;
                powerManagement.enable = lib.mkDefault true;
                # Fine-grained power management (D3 power gating) is incompatible
                # with PRIME sync and only useful on offload setups.
                powerManagement.finegrained = lib.mkDefault false;
                nvidiaSettings = lib.mkDefault true;
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

          (lib.mkIf cfg.prime.enable {
            services.xserver.videoDrivers = lib.mkForce [ "nvidia" ];

            hardware.nvidia.prime = {
              offload.enable = lib.mkForce false;
              sync.enable = true;
              inherit (cfg.prime) intelBusId nvidiaBusId;
            };
          })
        ]
      );
    };
in
{
  flake.nixosModules.nvidia-gpu = NvidiaGpuModule;
}
