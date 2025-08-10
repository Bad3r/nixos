# Generic NVIDIA module for systems that need it
# This is CORRECT as a named module - used by SOME systems, not ALL
# MUST match golden standard EXACTLY - no additions!
{
  flake.modules.nixos.nvidia-gpu = {
    # Use specialisation pattern from golden standard
    specialisation.nvidia-gpu.configuration = {
      services.xserver.videoDrivers = [ "nvidia" ];
      # NO hardware.graphics.enable - not in golden standard!
    };
  };
  
  # This "floating" code is CORRECT - golden standard has it too!
  # ONLY include packages that are in golden standard
  nixpkgs.allowedUnfreePackages = [
    "nvidia-x11"
    "nvidia-settings"
    # NO nvidia-persistenced - not in golden standard!
  ];
}