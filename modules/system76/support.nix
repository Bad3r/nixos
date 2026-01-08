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
        # Selective System76 hardware support:
        # - kernel-modules: Fan monitoring via hwmon, EC communication
        # - firmware-daemon: Firmware updates via fwupd/LVFS
        # - power-daemon: DISABLED - using thermald for thermal management instead
        hardware.system76 = {
          kernel-modules.enable = true;
          firmware-daemon.enable = true;
          power-daemon.enable = false;
        };

        # System76-specific kernel parameters
        boot.kernelParams = [ "system76_acpi.brightness_hwmon=1" ];

        # Enable LVFS firmware updates
        services.fwupd.enable = true;
      };
    };
}
