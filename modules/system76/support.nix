_: {
  flake.nixosModules.system76-support =
    { pkgs, ... }:
    {
      hardware.system76.enableAll = true;
      environment.systemPackages = with pkgs; [
        system76-firmware
        firmware-manager
        system76-keyboard-configurator
      ];

      # System76-specific kernel parameters
      boot.kernelParams = [
        "system76_acpi.brightness_hwmon=1"
      ];
    };
}
