_: {
  configurations.nixos.songbird.module =
    { pkgs, ... }:
    {
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
        # NVDEC via nvidia-vaapi-driver stays the session's libva default. The
        # "intel-media" fallback for Xid 31 MMU faults under decode churn drops
        # that driver and routes libva to the Xe-LPG iGPU at 0000:00:02.0.
        vaapi.backend = "nvidia";
      };

      # The iGPU's libva driver beside nvidia-vaapi-driver, for apps that
      # decode or encode on 0000:00:02.0 under their own LIBVA_DRIVER_NAME=iHD.
      hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

      # Suspend/hibernate VRAM preservation
      # (nvidia.NVreg_PreserveVideoMemoryAllocations=1 plus the
      # nvidia-suspend/hibernate/resume units) comes from
      # hardware.nvidia.powerManagement.enable, which the shared module
      # defaults on; the cryptswap volume in hardware-config.nix is the
      # hibernation target.
    };
}
