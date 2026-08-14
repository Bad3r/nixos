_: {
  configurations.nixos.system76.module =
    { config, lib, ... }:
    let
      cfg = config.system76.gpu;
      intelBusFields =
        let
          matched = builtins.match "PCI:([0-9]{1,3})(@([0-9]{1,10}))?:([0-9]{1,2}):([0-9])" cfg.intelBusId;
        in
        if matched == null then
          throw (
            "system76.gpu.intelBusId: expected decimal PCI:bus[@domain]:device:function "
            + "with bus 1-3 digits, optional domain 1-10 digits, device 1-2 digits, "
            + "and function 1 digit, got '${cfg.intelBusId}'"
          )
        else
          {
            bus = lib.elemAt matched 0;
            domain = if lib.elemAt matched 2 == null then "0" else lib.elemAt matched 2;
            device = lib.elemAt matched 3;
            function = lib.elemAt matched 4;
          };
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
            PCI address for the Intel iGPU, in Xorg's decimal
            `PCI:bus@domain:device:function` form; the domain may be omitted when it
            is 0. Used for PRIME sync when `mode = "hybrid-sync"`, and as the source
            of the `videoDecodeDevice` default in both modes. Unless
            `videoDecodeDevice` is overridden explicitly, an incorrect value can point
            the default Chromium and libva routing at the wrong render node and make
            hardware video decode fall back to software even with PRIME disabled.
            Determine the slot via `lspci -nn | grep VGA` and convert its hexadecimal
            components to decimal.
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
            "/dev/dri/by-path/pci-${intelDomainHexPadded intelBusFields.domain}:${intelBusHexPadded intelBusFields.bus}"
            + ":${intelBusHexPadded intelBusFields.device}.${intelBusHex intelBusFields.function}-render";
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

        chromeExtraFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional flags exported to Chromium browsers through
            `CHROME_EXTRA_FLAGS`. The required render-node flag is prepended
            automatically, so adding flags here cannot disable hardware video decode.
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
            CHROME_EXTRA_FLAGS = lib.mkDefault (
              lib.concatStringsSep " " ([ videoDeviceFlag ] ++ cfg.chromeExtraFlags)
            );
            LIBVA_DRM_DEVICE = lib.mkDefault cfg.videoDecodeDevice;
            LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
          };
        }
      ];
    };
}
