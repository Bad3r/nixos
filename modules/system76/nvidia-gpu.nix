_: {
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      # Install NVIDIA driver (needed even for Wayland offload)
      services.xserver.videoDrivers = [ "nvidia" ];

      # Graphics hardware configuration
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          nvidia-vaapi-driver
          vaapiVdpau
          intel-media-driver
          libva-utils
          vulkan-validation-layers
        ];
      };

      # NVIDIA hardware configuration for Wayland-friendly PRIME Offload
      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
        prime = {
          # Use render offload instead of PRIME Sync for Wayland stability
          sync.enable = false;
          offload.enable = true;
          offload.enableOffloadCmd = true; # provides `nvidia-offload`
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
        };
      };

      # Remove global NVIDIA env forcing; prefer defaults for hybrid iGPU+dGPU on Wayland
      # (Per-app overrides like LIBVA_DRIVER_NAME=nvidia can still be used when needed.)
    };
}
