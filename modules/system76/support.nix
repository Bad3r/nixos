_: {
  flake.nixosModules.system76-support = _: {
    hardware.system76.enableAll = true;

    # System76-specific kernel parameters
    boot.kernelParams = [
      "system76_acpi.brightness_hwmon=1"
    ];

    # Enable LVFS firmware updates
    services.fwupd.enable = true;
  };
}
