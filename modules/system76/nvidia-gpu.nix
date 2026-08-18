_: {
  configurations.nixos.system76.module =
    { config, lib, ... }:
    let
      cfg = config.system76.gpu;
      intelBusFields =
        let
          matched = builtins.match "PCI:([0-9]{1,3})(@([0-9]{1,10}))?:([0-9]{1,2}):([0-7])" cfg.intelBusId;
          fields =
            if matched == null then
              null
            else
              {
                bus = lib.toIntBase10 (lib.elemAt matched 0);
                domain = if lib.elemAt matched 2 == null then 0 else lib.toIntBase10 (lib.elemAt matched 2);
                device = lib.toIntBase10 (lib.elemAt matched 3);
                function = lib.toIntBase10 (lib.elemAt matched 4);
              };
        in
        # Check ranges, not just digit counts: a field that parses but overflows its
        # PCI width would otherwise abort inside lib.fixedWidthString, naming lib
        # rather than the option that carries the bad value.
        if fields == null || fields.bus > 255 || fields.device > 31 then
          throw (
            "system76.gpu.intelBusId: expected decimal PCI:bus[@domain]:device:function "
            + "with bus 0-255, device 0-31, function 0-7, and an optional domain, "
            + "got '${cfg.intelBusId}'"
          )
        else
          fields;
      # sysfs names a PCI device "%04x:%02x:%02x.%d". Those widths are minimums, so a
      # domain above 0xffff widens its field instead of being rejected, and the
      # function stays decimal.
      intelBusPadded =
        width: part:
        let
          hex = lib.toLower (lib.toHexString part);
        in
        if lib.stringLength hex >= width then hex else lib.fixedWidthString width "0" hex;
      videoDeviceFlag = "--hardware-video-device-path=${cfg.videoDecodeDevice}";
      # Chromium re-splits CHROME_EXTRA_FLAGS on whitespace, but its tokenizer honours
      # a quoted whole token and trims the outer quotes, so quoting keeps one list
      # entry as exactly one argument. A quote character inside an entry has no
      # representation, hence the assertion below.
      # The quote is single, not double: sessionVariables land in /etc/pam/environment
      # as NAME DEFAULT="<value>", which the generator interpolates unescaped, so a
      # double quote would close that value early and truncate the line. Chromium's
      # tokenizer accepts either (set_quote_chars("\"'")), and ' is inert in that file.
      hasQuote = flag: builtins.match ".*[\"'].*" flag != null;
      # /etc/pam/environment is line-oriented (one NAME DEFAULT="<value>" record per
      # variable), so a raw line break inside a value has no representation either:
      # it would split one record into two and drop everything after it.
      hasLineBreak = flag: builtins.match ".*[\n\r].*" flag != null;
      # pam_env(8) reads this file as its conffile and expands ${VAR} and @{PAM_ITEM}
      # inside a DEFAULT= value with no escape for either character (man pam_env.conf);
      # nixpkgs' own generator relies on this to make $HOME/$USER work in
      # sessionVariables (nixos/modules/config/system-environment.nix's replaceEnvVars).
      # An entry carrying $ or @ is rewritten before any browser sees it.
      hasExpansion = flag: builtins.match ".*[$@].*" flag != null;
      quoteFlag = flag: if builtins.match ".*[[:space:]].*" flag == null then flag else "'${flag}'";
      unquotableFlags = lib.filter (flag: hasQuote flag || hasLineBreak flag || hasExpansion flag) (
        cfg.chromeExtraFlags ++ [ videoDeviceFlag ]
      );
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
            is 0. Fields are range-checked against their PCI widths: bus 0-255,
            device 0-31, function 0-7, and any domain. Used for PRIME sync when
            `mode = "hybrid-sync"`, and as the source
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
            "/dev/dri/by-path/pci-${intelBusPadded 4 intelBusFields.domain}:${intelBusPadded 2 intelBusFields.bus}"
            + ":${intelBusPadded 2 intelBusFields.device}.${toString intelBusFields.function}-render";
          defaultText = lib.literalExpression ''"/dev/dri/by-path/pci-<intelBusId as a sysfs address>-render"'';
          example = "/dev/dri/by-path/pci-0000:00:02.0-render";
          description = ''
            Intel render node offered to VA-API consumers. When omitted, the by-path
            default is derived from the decimal Xorg `PCI:bus@domain:device:function`
            components (with domain 0 when omitted), formatted as sysfs'
            `%04x:%02x:%02x.%d` address. The by-path form is stable because renderD
            numbering follows driver probe order, not the PCI slot.
          '';
        };

        chromeExtraFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional flags exported to Chromium browsers through
            `CHROME_EXTRA_FLAGS`. The derived render-node flag is appended last, and
            Chromium keeps the last occurrence of a repeated switch, so flags added
            here cannot displace it. Change the render node through
            `videoDecodeDevice` instead.

            One entry is one argument: entries containing whitespace are quoted, since
            Chromium re-splits the variable on whitespace. An entry containing a quote
            character, a line break, or a `$`/`@` expansion character cannot be encoded
            and fails the assertion.
          '';
          example = [ "--host-resolver-rules=MAP * 127.0.0.1" ];
        };
      };

      config = {
        assertions = [
          {
            assertion = unquotableFlags == [ ];
            message =
              "system76.gpu: entries are quoted into CHROME_EXTRA_FLAGS, so neither "
              + "chromeExtraFlags nor the flag derived from videoDecodeDevice may contain "
              + "a quote character, a line break, or a $/@ expansion character. "
              + "Offending entries: "
              + lib.concatStringsSep ", " unquotableFlags;
          }
        ];

        # Blacklist nouveau to avoid conflicts with proprietary NVIDIA driver.
        # i915 is deliberately absent: internal HDA/SOF audio on this chassis can
        # depend on Intel graphics-side plumbing even when NVIDIA renders X11, and
        # the iGPU also backs the only VA-API decode target configured below.
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
        # iGPU node restores hardware decode. The browser binary reads this variable
        # itself (AppendExtraArgumentsToCommandLine in chrome/app/chrome_main_linux.cc,
        # not a launcher script), which covers new ones without per-package wiring.
        # It appends onto the parsed command line, so it also outranks the wrapper
        # --add-flags this repo bakes into its Chromium packages. Chromium keeps the
        # last occurrence of a repeated switch, hence videoDeviceFlag goes last.
        # Keep libva on the same Intel node and iHD driver in both modes so non-Chromium
        # VA-API consumers do not fall back to render-node probe order.
        # VDPAU_DRIVER is intentionally unset: VDPAU is legacy, and pointing it at
        # nvidia would route back into the NVDEC path that faults above.
        # sessionVariables is PAM-initialised, so GUI apps launched outside a shell
        # inherit this routing too, not just terminal-spawned ones.
        environment.sessionVariables = {
          CHROME_EXTRA_FLAGS = lib.mkDefault (
            lib.concatMapStringsSep " " quoteFlag (cfg.chromeExtraFlags ++ [ videoDeviceFlag ])
          );
          LIBVA_DRM_DEVICE = lib.mkDefault cfg.videoDecodeDevice;
          LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
        };
      };
    };
}
