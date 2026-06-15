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
            # VA-API decode routes through Intel Quick Sync (iHD), not NVDEC.
            # nvidia-vaapi-driver's VA-API -> NVDEC handoff faults under decode-context
            # churn: switching videos quickly or reloading stalled SMB/SFTP streams
            # produces an Xid 31 MMU page fault on ENGINE NVDEC, hanging the dGPU and
            # freezing the session (the dGPU drives the display in nvidia-only mode).
            # Intel UHD 630 (i915 stays loaded here, see the nvidia-only branch) decodes
            # H.264/HEVC/VP9 in hardware; AV1 falls back to software. mpv is unaffected
            # because hwdec=auto uses FFmpeg NVCUVID (nvdec), never libva.
            # (generic graphics enablement lives in modules/hosts/common/graphics-support.nix)
            graphics.extraPackages = with pkgs; [
              intel-media-driver
              vulkan-validation-layers
            ];

            nvidia = {
              # GTX 1070 Max-Q is supported by the 580.xx legacy branch; newer production drivers ignore it.
              package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
              modesetting.enable = true;
              # Suppress nixpkgs' default nvidia-vaapi-driver install (this option
              # defaults to true and is its only consumer). VA-API decode is handled by
              # Intel iHD instead; see the graphics.extraPackages note for the Xid 31
              # NVDEC fault rationale.
              videoAcceleration = false;
              powerManagement.enable = true;
              # Fine-grained power management (D3 power gating) is incompatible with PRIME sync.
              # Sync mode keeps the dGPU always on to drive display output through the iGPU.
              # To enable finegrained, switch system76.gpu.mode to use offload instead.
              powerManagement.finegrained = false;
              open = false;
              nvidiaSettings = true;
            };

            # Containers: NVIDIA container toolkit for GPU passthrough
            nvidia-container-toolkit.enable = true;
          };

          # Diagnostics: vulkaninfo and glxinfo
          environment.systemPackages = with pkgs; [
            vulkan-tools
            mesa-demos
          ];
        }

        (lib.mkIf (cfg.mode == "nvidia-only") {
          # Keep the Intel iGPU disabled so only the dGPU drives displays.
          hardware.nvidia.prime = {
            offload.enable = lib.mkForce false;
            sync.enable = lib.mkForce false;
          };

          # Do not blacklist i915: internal HDA/SOF audio on this chassis can
          # depend on Intel graphics-side plumbing even when NVIDIA renders X11.

          # Route VA-API to Intel Quick Sync (iHD), not NVDEC, to avoid the Xid 31
          # decode fault (see graphics.extraPackages above). i915 stays loaded here,
          # and the by-path render node keeps libva off the NVIDIA DRM device.
          # VDPAU_DRIVER is intentionally unset: VDPAU is legacy, and pointing it at
          # nvidia would route back into NVDEC.
          # sessionVariables (PAM-initialised) so GUI apps launched outside a
          # shell inherit the iHD routing, not just terminal-spawned ones.
          environment.sessionVariables = {
            LIBVA_DRM_DEVICE = lib.mkDefault "/dev/dri/by-path/pci-0000:00:02.0-render";
            LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
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
