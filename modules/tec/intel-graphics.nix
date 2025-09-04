_: {
  configurations.nixos.tec.module =
    { pkgs, ... }:
    {
      # Intel-specific graphics packages for hardware acceleration
      hardware.graphics.extraPackages = with pkgs; [
        intel-media-driver # VAAPI driver for Broadwell+ (2014+) - provides iHD
        intel-compute-runtime # OpenCL runtime for Intel GPUs
        vaapiIntel # Legacy VAAPI driver for older Intel GPUs (provides i965)
        vaapiVdpau # VAAPI-VDPAU bridge for compatibility
        libvdpau-va-gl # VDPAU driver using VA-API/OpenGL
      ];

      # Intel-specific kernel parameters for better performance
      boot.kernelParams = [
        "i915.enable_guc=2" # Enable GuC firmware for better GPU scheduling
        "i915.enable_fbc=1" # Enable frame buffer compression for power saving
      ];
    };
}
