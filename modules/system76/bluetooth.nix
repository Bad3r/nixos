{ lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings.General = {
          Experimental = true;
          # Identify as Apple (VID 0x004C) over the DID profile so AirPods
          # and other Apple-aware peripherals expose features otherwise
          # gated to Apple hosts.
          DeviceID = "bluetooth:004C:0000:0000";
        };
      };

      environment.systemPackages = lib.mkAfter [ pkgs.bluetui ];
    };
}
