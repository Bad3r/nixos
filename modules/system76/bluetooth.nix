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

      # Bluetooth radios: disable USB autosuspend. The kernel default of 2s
      # autosuspend combined with wakeup=disabled on the Intel 8087:0a2b
      # radio drops HID-over-GATT peripherals (symptom: MX Master 3
      # disconnects after idle and only re-pairing restores it).
      # ACTION=="add|change" also catches udevadm trigger (nixos-rebuild
      # switch) and resume-from-sleep events; ENV{DEVTYPE}=="usb_device"
      # scopes the match to device nodes so interface objects are not
      # probed (udevadm verify rejects bare DEVTYPE== as an invalid key).
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{bDeviceClass}=="e0", ATTR{bDeviceSubClass}=="01", ATTR{bDeviceProtocol}=="01", TEST=="power/control", ATTR{power/control}="on"
      '';

      environment.systemPackages = lib.mkAfter [ pkgs.bluetui ];
    };
}
