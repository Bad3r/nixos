_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      # Install NVIDIA driver
      services.xserver.videoDrivers = [ "nvidia" ];

      # NVIDIA-related graphics libraries (generic graphics enablement lives in pc/graphics-support.nix)
      hardware.graphics.extraPackages = with pkgs; [
        nvidia-vaapi-driver
        vaapiVdpau
        vulkan-validation-layers
      ];

      # NVIDIA hardware configuration (dGPU-only; no PRIME offload/sync)
      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
      };

      # Xorg tear-free: Force full composition pipeline for NVIDIA
      services.xserver.screenSection = lib.mkDefault ''
        Option "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
      '';

      # Prefer NVIDIA VA-API globally (NVDEC). Override per-app if needed.
      environment.variables.LIBVA_DRIVER_NAME = lib.mkForce "nvidia";
    };
}
