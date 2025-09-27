_: {
  flake.nixosModules.intel-gpu =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.pc.intel-gpu;
    in
    {
      options.pc.intel-gpu.enable = lib.mkEnableOption "Enable Intel GPU VA-API support" // {
        default = true;
      };

      config = lib.mkIf cfg.enable {
        # Intel VA-API driver
        hardware.graphics = {
          enable = true;
          extraPackages = [ pkgs.intel-media-driver ];
        };

        # Prefer Intel media driver when VA-API is used (can be overridden per-host)
        environment.variables.LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
      };
    };
}
