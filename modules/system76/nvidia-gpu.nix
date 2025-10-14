_: {
  configurations.nixos.system76.module =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.system76.gpu;
    in
    {
      options.system76.gpu = {
        mode = lib.mkOption {
          type = lib.types.enum [
            "hybrid-sync"
            "nvidia-only"
          ];
          default = "hybrid-sync";
          description = "Select how the System76 laptop wires the NVIDIA GPU into X.Org.";
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

      config = lib.mkMerge [
        {
          services.xserver = {
            videoDrivers = lib.mkDefault [ "nvidia" ];
            # Tear-free: Force full composition pipeline for NVIDIA
            screenSection = lib.mkDefault ''
              Option "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
            '';
          };

          hardware = {
            # NVIDIA-related graphics libraries (generic graphics enablement lives in pc/graphics-support.nix)
            graphics.extraPackages = with pkgs; [
              nvidia-vaapi-driver
              vulkan-validation-layers
            ];

            nvidia = {
              modesetting.enable = true;
              powerManagement.enable = true;
              powerManagement.finegrained = false;
              open = false;
              nvidiaSettings = true;
            };

            # Containers: NVIDIA container toolkit for GPU passthrough
            nvidia-container-toolkit.enable = true;
          };

        }

        (lib.mkIf (cfg.mode == "nvidia-only") {
          # Keep the Intel iGPU disabled so only the dGPU drives displays.
          hardware.nvidia.prime = {
            offload.enable = lib.mkForce false;
            sync.enable = lib.mkForce false;
          };

          boot.blacklistedKernelModules = lib.mkAfter [ "i915" ];

          # Prefer NVIDIA VA-API/VDPAU implementations in dedicated mode.
          environment.variables = {
            LIBVA_DRIVER_NAME = lib.mkDefault "nvidia";
            VDPAU_DRIVER = lib.mkDefault "nvidia";
          };
        })

        (lib.mkIf (cfg.mode == "hybrid-sync") {
          services.xserver.videoDrivers = lib.mkForce [
            "nvidia"
          ];

          # Enable PRIME sync so the internal panel stays driven by the iGPU but surfaces are rendered on NVIDIA.
          hardware.nvidia.prime = {
            offload.enable = lib.mkForce false;
            sync.enable = true;
            inherit (cfg) intelBusId nvidiaBusId;
          };
        })
      ];
    };
}
