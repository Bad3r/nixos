_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      # Install NVIDIA driver (needed even for Wayland offload)
      services.xserver.videoDrivers = [ "nvidia" ];

      # Graphics hardware configuration
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          nvidia-vaapi-driver
          vaapiVdpau
          libva-utils
          vulkan-validation-layers
        ];
      };

      # NVIDIA hardware configuration (dGPU-only; no PRIME offload/sync)
      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
      };

      # Prefer NVIDIA VA-API globally (NVDEC). Override per-app if needed.
      environment.variables.LIBVA_DRIVER_NAME = lib.mkForce "nvidia";
    };
}
