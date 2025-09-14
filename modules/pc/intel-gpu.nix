_: {
  flake.nixosModules.intel-gpu =
    { pkgs, lib, ... }:
    {
      # Intel VA-API driver
      hardware.graphics = {
        enable = true;
        extraPackages = [ pkgs.intel-media-driver ];
      };

      # Prefer Intel media driver when VA-API is used
      environment.variables.LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
    };
}
