{ config, lib, ... }:
{
  configurations.nixos.system76.module = { pkgs, ... }: {
    # Enable graphics if needed (not in generic module)
    hardware.graphics.enable = true;
    
    # Hardware-specific NVIDIA settings
    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = false;  # Matches golden standard ganoderma
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      
      # System76-specific bus IDs
      prime = {
        sync.enable = true;
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
    
    # Additional NVIDIA-specific environment variables
    environment.variables = {
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      LIBVA_DRIVER_NAME = "nvidia";
    };
    
    # Additional unfree packages if needed (beyond generic module)
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "nvidia-persistenced"  # If needed for this specific system
    ];
  };
}