# modules/linux/hardware/nvidia.nix
{ config, pkgs, ... }:

{
  boot = {
    blacklistedKernelModules = [ "nouveau" ]; # Disable open-source driver

    # NVIDIA modules for initrd (MUST come before other graphics modules)
    initrd.kernelModules =
      [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

    extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

    kernelParams = [
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      "nvidia.NVreg_EnableGpuFirmware=1"
    ];
  };

  services.xserver.videoDrivers = [ "nvidia" ]; # Force NVIDIA driver

  hardware = {
    graphics = {
      enable = true; # Formerly hardware.opengl.enable
      enable32Bit = true; # Required for 32-bit applications
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        vaapiVdpau
        libvdpau-va-gl
        intel-media-driver
      ];
    };

    nvidia = {
      modesetting.enable = true; # Required for Wayland compatibility
      powerManagement = {
        enable = true; # Fixes GPU power state transitions
        finegrained = false; # Disable for desktop systems
      };
      open = false; # Use proprietary driver
      nvidiaSettings = false; # Disable if not using nvidia-settings
      prime = {
        # CONFIRM THESE WITH lspci -nn | grep -E "VGA|3D"
        intelBusId = "PCI:0:2:0"; # Typical Intel iGPU
        nvidiaBusId = "PCI:1:0:0"; # Typical NVIDIA dGPU
        sync.enable = true; # Enable PRIME synchronization
      };
      package =
        config.boot.kernelPackages.nvidia_x11; # Explicit package binding
    };
  };

  # Required for NVIDIA DRM kernel modesetting
  environment.variables = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };
}
