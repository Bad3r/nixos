{
  flake.nixosModules.system76-support =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.hardware.system76.extended;
    in
    {
      options.hardware.system76.extended = {
        enable = lib.mkEnableOption "System76 hardware support with firmware updates";
      };

      config = lib.mkIf cfg.enable {
        hardware.system76.enableAll = true;

        # System76-specific kernel parameters
        boot.kernelParams = [ "system76_acpi.brightness_hwmon=1" ];

        # Enable LVFS firmware updates
        services.fwupd.enable = true;
      };
    };
}
