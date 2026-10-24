_: {
  configurations.nixos.songbird.module = {
    # nouveau bound the RTX 5080 on the stock install; nixpkgs' hardware.nvidia
    # module blacklists it once videoDrivers carries "nvidia", so the open kernel
    # modules own 0000:02:00.0 (10de:2c02).
    gpu.nvidia = {
      enable = true;
      # Blackwell GB203: NVIDIA's open kernel modules are the only supported
      # flavor; the driver branch is the shared module's default
      # (nvidiaPackages.production, resolved against the CachyOS kernel
      # above). hardware.nvidia.gsp follows `open` automatically.
      open = true;
      # NVDEC via nvidia-vaapi-driver. Fallback if Xid 31 MMU faults appear
      # under decode churn: "intel-media", which routes libva to the Xe-LPG
      # iGPU at 0000:00:02.0.
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
