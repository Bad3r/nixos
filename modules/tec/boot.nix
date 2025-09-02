_: {
  configurations.nixos.tec.module =
    { pkgs, ... }:
    {
      # Use latest kernel packages
      boot.kernelPackages = pkgs.linuxPackages_latest;

      boot = {
        # Intel graphics support
        initrd.kernelModules = [ "i915" ];

        # Additional kernel parameters for Intel graphics
        kernelParams = [
          "i915.enable_guc=2"
          "i915.enable_fbc=1"
        ];
      };
    };
}
