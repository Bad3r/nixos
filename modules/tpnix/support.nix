{
  flake.nixosModules.tpnix-support =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.hardware.tpnix.extended;
    in
    {
      options.hardware.tpnix.extended = {
        enable = lib.mkEnableOption "tpnix host hardware support hooks";
      };

      # Intentionally empty by default. Host-specific hardware support can be
      # added here later without coupling tpnix to System76 modules.
      config = lib.mkIf cfg.enable { };
    };
}
