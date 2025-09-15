_: {
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      # Boot-time selectable specialisation: NVIDIA dGPU as primary (X11, PRIME Sync)
      # - Keeps iGPU enabled (not blacklisted)
      # - Uses NVIDIA as the primary renderer; suitable when external displays rely on the dGPU
      # - Switch to this entry from the bootloader when you need dGPU-first behavior
      specialisation."nvidia-dgpu-primary-x11".configuration = {
        # Use X11 session for reliable PRIME Sync wiring
        services.displayManager.sddm.wayland.enable = lib.mkForce false;
        services.displayManager.defaultSession = lib.mkForce "plasma";

        hardware.nvidia.prime = {
          # Make dGPU the primary renderer
          sync.enable = lib.mkForce true;
          # Ensure offload is not active in this specialisation
          offload.enable = lib.mkForce false;
          # Avoid assertion from upstream module: enableOffloadCmd requires offload/reverseSync
          offload.enableOffloadCmd = lib.mkForce false;
        };
      };
    };
}
