_: {
  configurations.nixos.system76.module =
    { config, lib, ... }:
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

      config = {
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
          # FFmpeg NVCUVID (nvdec), never libva. i915 stays off the blacklist: internal
          # HDA/SOF audio on this chassis can depend on Intel graphics-side plumbing
          # even when NVIDIA renders X11.
          vaapi.backend = "intel-media";
          prime = {
            # PRIME sync keeps the internal panel on the iGPU while NVIDIA renders;
            # in nvidia-only mode this stays disabled and only the dGPU drives displays.
            enable = cfg.mode == "hybrid-sync";
            inherit (cfg) intelBusId nvidiaBusId;
          };
        };

        # libva selects a driver by name only, so iHD keeps every VA-API client off
        # nvidia-vaapi-driver in both modes (see the vaapi.backend note above);
        # render-node selection stays the client's, see modules/browsers/gecko-env.nix.
        # VDPAU_DRIVER is intentionally unset: VDPAU is legacy, and pointing it at
        # nvidia would route back into NVDEC.
        # sessionVariables (PAM-initialised) so GUI apps launched outside a shell
        # inherit the iHD routing, not just terminal-spawned ones.
        environment.sessionVariables.LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
      };
    };
}
