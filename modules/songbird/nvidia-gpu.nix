_: {
  configurations.nixos.songbird.module =
    { config, lib, ... }:
    {
      # nouveau bound the RTX 5080 on the stock install; keep it out so the
      # NVIDIA open kernel modules own 0000:02:00.0 (10de:2c02).
      boot.blacklistedKernelModules = [ "nouveau" ];

      gpu.nvidia = {
        enable = true;
        # Blackwell GB203: NVIDIA's open kernel modules are the only supported
        # flavor and need the 570+ branch (production is 595.x on the pinned
        # nixpkgs); hardware.nvidia.gsp follows `open` automatically.
        package = config.boot.kernelPackages.nvidiaPackages.production;
        open = true;
        # NVDEC via nvidia-vaapi-driver (docs/songbird/nixos-setup.md,
        # decision 13). Documented fallback if Xid 31 MMU faults appear under
        # decode churn: "intel-media", which routes libva to the Xe-LPG iGPU
        # at 0000:00:02.0.
        vaapi.backend = "nvidia";
        # The XMI Mi Monitor on DFP-5 advertises 2560x1440@60 as its EDID
        # preferred mode and 180/165/144/120 as alternates, so
        # nvidia-auto-select lands on 60 and RandR silently reverts there on
        # every hotplug and DPMS wake.
        metamode = "2560x1440_144";
        # Single-GPU desktop: PRIME stays off (shared-module default). The
        # iGPU remains present for VA-API fallback and GPU-less bring-up only.
      };

      # gecko-env.nix exports LIBVA_DRIVER_NAME=nvidia session-wide once
      # nvidia-vaapi-driver is installed, but libva still picks the DRM node by
      # enumeration order and renderD128 is the Intel iGPU here. Pin the node by
      # PCI path so the NVDEC driver is never handed the Intel fd, and so a
      # probe-order swap between boots cannot move decode. Keyed on
      # vaapi.backend, because the intel-media fallback above drops
      # nvidia-vaapi-driver: a node left pointing at the NVIDIA card would then
      # resolve the driver name to one that is no longer installed and fail
      # vaInitialize outright, rather than moving decode to the iGPU.
      # mkDefault like the system76 pin and gecko-env.nix's VA-API set: the
      # option's type merges equal-priority definitions with mergeEqualOption,
      # so a plain value here would make a second definition of this key a hard
      # eval failure on this host alone rather than an override.
      environment.sessionVariables.LIBVA_DRM_DEVICE = lib.mkDefault (
        if config.gpu.nvidia.vaapi.backend == "intel-media" then
          "/dev/dri/by-path/pci-0000:00:02.0-render"
        else
          "/dev/dri/by-path/pci-0000:02:00.0-render"
      );

      # Suspend/hibernate VRAM preservation
      # (nvidia.NVreg_PreserveVideoMemoryAllocations=1 plus the
      # nvidia-suspend/hibernate/resume units) comes from
      # hardware.nvidia.powerManagement.enable, which the shared module
      # defaults on; the cryptswap volume in hardware-config.nix is the
      # hibernation target.
    };
}
