_: {
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      # X11 video driver
      services.xserver.videoDrivers = [ "nvidia" ];

      # Graphics hardware configuration
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          nvidia-vaapi-driver
          vaapiVdpau
          libvdpau-va-gl
          intel-media-driver
        ];
      };

      # NVIDIA hardware configuration
      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
        prime = {
          sync.enable = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
        };
      };

      # NVIDIA environment variables
      environment.variables = {
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        LIBVA_DRIVER_NAME = "nvidia";
      };
    };
}
