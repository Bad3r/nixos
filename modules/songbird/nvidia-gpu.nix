_: {
  configurations.nixos.songbird.module =
    { config, ... }:
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
        # Single-GPU desktop: PRIME stays off (shared-module default). The
        # iGPU remains present for VA-API fallback and GPU-less bring-up only.
      };

      # Suspend/hibernate VRAM preservation
      # (nvidia.NVreg_PreserveVideoMemoryAllocations=1 plus the
      # nvidia-suspend/hibernate/resume units) comes from
      # hardware.nvidia.powerManagement.enable, which the shared module
      # defaults on; the cryptswap volume in hardware-config.nix is the
      # hibernation target.
    };
}
