_: {
  configurations.nixos.system76.module =
    { config, lib, ... }:
    let
      cfg = config.system76.gpu;
      intelBusParts = lib.splitString ":" (lib.removePrefix "PCI:" cfg.intelBusId);
      intelBusDomainParts = lib.splitString "@" (lib.elemAt intelBusParts 0);
      intelBusHex = part: lib.toLower (lib.toHexString (lib.toIntBase10 part));
      intelBusHexPadded = part: lib.fixedWidthString 2 "0" (intelBusHex part);
      intelDomainHexPadded = part: lib.fixedWidthString 4 "0" (intelBusHex part);
      videoDeviceFlag = "--hardware-video-device-path=${cfg.videoDecodeDevice}";
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
            PCI address for the Intel iGPU when PRIME sync is enabled, in Xorg's
            decimal `PCI:bus@domain:device:function` form. Determine the slot via
            `lspci -nn | grep VGA` and convert its hexadecimal components if the
            default does not match this chassis. The domain may be omitted when it is 0.
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

        videoDecodeDevice = lib.mkOption {
          type = lib.types.str;
          default =
            "/dev/dri/by-path/pci-${
              intelDomainHexPadded (
                if builtins.length intelBusDomainParts == 2 then lib.elemAt intelBusDomainParts 1 else "0"
              )
            }:${intelBusHexPadded (lib.elemAt intelBusDomainParts 0)}"
            + ":${intelBusHexPadded (lib.elemAt intelBusParts 1)}.${intelBusHex (lib.elemAt intelBusParts 2)}-render";
          defaultText = lib.literalExpression ''"/dev/dri/by-path/pci-<intelBusId as a sysfs address>-render"'';
          example = "/dev/dri/renderD128";
          description = ''
            Intel render node offered to VA-API consumers. When omitted, the by-path
            default is derived from the decimal Xorg `PCI:bus@domain:device:function`
            components (with domain 0 when omitted), converted to the hexadecimal sysfs
            address. The by-path form is stable because renderD numbering follows driver
            probe order, not the PCI slot.
          '';
        };
      };

      config = lib.mkMerge [
        {
          # Blacklist nouveau to avoid conflicts with proprietary NVIDIA driver
          boot.blacklistedKernelModules = [ "nouveau" ];

          boot.kernelParams = [
            "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
            "nvidia.NVreg_EnableGpuFirmware=1"
          ];

          gpu.nvidia = {
            enable = true;
            # GTX 1070 Max-Q is supported by the 580.xx legacy branch; newer production drivers ignore it.
            package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
            # Pascal predates the open kernel modules.
            open = false;
            # nvidia-vaapi-driver's VA-API -> NVDEC handoff faults under decode-context
            # churn on this chassis: switching videos quickly or reloading stalled
            # SMB/SFTP streams produces an Xid 31 MMU page fault on ENGINE NVDEC,
            # hanging the dGPU and freezing the session (the dGPU drives the display
            # in nvidia-only mode). Intel UHD 630 decodes H.264/HEVC/VP9 in hardware;
            # AV1 falls back to software. mpv is unaffected because hwdec=auto uses
            # FFmpeg NVCUVID (nvdec), never libva.
            vaapi.backend = "intel-media";
            prime = {
              # PRIME sync keeps the internal panel on the iGPU while NVIDIA renders.
              enable = cfg.mode == "hybrid-sync";
              inherit (cfg) intelBusId nvidiaBusId;
            };
          };

          # Chromium picks a VA-API render node by matching whichever GPU it renders
          # on, then rejects nvidia-drm outright (crbug.com/1492880). NVIDIA renders in
          # both modes here, so the match lands on the dGPU, the pre-sandbox VA-API
          # init finds nothing, and every Chromium app decodes in software. Naming the
          # iGPU node restores hardware decode. The browsers read this variable
          # themselves, which covers new ones without any per-package wiring.
          # Keep libva on the same Intel node and iHD driver in both modes so non-Chromium
          # VA-API consumers do not fall back to render-node probe order.
          environment.sessionVariables = {
            CHROME_EXTRA_FLAGS = lib.mkDefault videoDeviceFlag;
            LIBVA_DRM_DEVICE = lib.mkDefault cfg.videoDecodeDevice;
            LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
          };
        }
      ];
    };
}
