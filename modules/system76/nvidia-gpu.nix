_: {
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      # Xorg + NVIDIA
      services.xserver = {
        videoDrivers = [ "nvidia" ];
        # Tear-free: Force full composition pipeline for NVIDIA
        screenSection = lib.mkDefault ''
          Option "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
        '';
      };

      # Hardware configuration
      hardware = {
        # NVIDIA-related graphics libraries (generic graphics enablement lives in pc/graphics-support.nix)
        graphics.extraPackages = with pkgs; [
          nvidia-vaapi-driver
          vulkan-validation-layers
        ];

        # NVIDIA driver (pure NVIDIA; no PRIME)
        nvidia = {
          modesetting.enable = true;
          powerManagement.enable = true;
          powerManagement.finegrained = false;
          open = false;
          nvidiaSettings = true;
        };

        # Containers: NVIDIA container toolkit for GPU passthrough
        nvidia-container-toolkit.enable = true;
      };

      # Environment
      environment = {
        # Prefer NVIDIA implementations by default (override per-app as needed)
        variables = {
          LIBVA_DRIVER_NAME = lib.mkDefault "nvidia";
          VDPAU_DRIVER = lib.mkDefault "nvidia";
        };
        # Diagnostics: vulkaninfo and glxinfo
        systemPackages = with pkgs; [
          vulkan-tools
          mesa-demos
        ];
      };

      # Docker GPU support for NVIDIA is configured via hardware.nvidia-container-toolkit

      # Host is NVIDIA dGPU-centric; ensure we don't enable Intel VA-API helpers here
      # Intel VA-API module is not imported for this host, so no explicit disable is needed.

      # Enforce System76 NVIDIA graphics mode at boot (no specialisations)
      # Removed Pop!_OS-style enforcement of graphics mode.
      # NixOS handles NVIDIA configuration via services.xserver + hardware.nvidia.
    };
}
