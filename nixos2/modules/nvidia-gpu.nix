# modules/nvidia-gpu.nix

{ config, pkgs, ... }:
{
  flake.modules.nixos.nvidia-gpu.services.xserver.videoDrivers = [ "nvidia" ];
  nixpkgs.allowedUnfreePackages = [
    "nvidia-x11"
    "nvidia-settings"
  ];

  boot = {
    blacklistedKernelModules = [ "nouveau" ]; # Disable open-source driver

    # NVIDIA modules for initrd (MUST come before other graphics modules)
    initrd.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];

    extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

    kernelParams = [
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      "nvidia.NVreg_EnableGpuFirmware=1"
    ];

    extraModprobeConfig = ''
      blacklist nouveau
      options nouveau modeset=0
    '';

  };

  nvidia = rec {
    open = false; # Use proprietary driver
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    #package = config.boot.kernelPackages.nvidia_x11;
    modesetting.enable = true; # Required for Wayland compatibility
    powerManagement = {
      enable = true; # Fixes GPU power state transitions
      finegrained = true;
    };
    prime = {
      # lspci -nn | grep -E "VGA|3D"
      intelBusId = "PCI:0:2:0"; # Intel iGPU
      nvidiaBusId = "PCI:1:0:0"; # NVIDIA dGPU
      #sync.enable = true; # Do not power off the GPU; conflicts with offload.enable
      offload.enable = powerManagement.finegrained;
      offload.enableOffloadCmd = prime.offload.enable;
    };
  };

  # Required for NVIDIA DRM kernel modesetting
  environment.variables = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };

}
