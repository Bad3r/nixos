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
        # System76 hardware support:
        # - kernel-modules: Fan monitoring via hwmon, EC communication
        # - firmware-daemon: Firmware updates via fwupd/LVFS
        # - power-daemon: Thermal management, power profiles, battery charge thresholds
        hardware.system76 = {
          kernel-modules.enable = true;
          firmware-daemon.enable = true;
          power-daemon.enable = true;
        };

        # System76-specific kernel parameters
        boot.kernelParams = [ "system76_acpi.brightness_hwmon=1" ];

        # Enable LVFS firmware updates
        services.fwupd.enable = true;
      };
    };
}
