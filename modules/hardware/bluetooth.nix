_: {
  flake.nixosModules.bluetooth =
    { lib, pkgs, ... }:
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings.General = {
          Experimental = true;
          # Spoof Apple host (VID 0x004C) over the DID profile so AirPods and
          # other Apple-aware peripherals expose battery and gesture features
          # otherwise gated to Apple hosts.
          DeviceID = "bluetooth:004C:0000:0000";
        };
      };

      # Disable USB autosuspend on Bluetooth radios. The kernel default of 2s
      # autosuspend drops HID-over-GATT peripherals after idle (re-pairing
      # required to recover). Match by USB Wireless Controller class
      # (e0/01/01) so the rule applies to any Bluetooth radio without
      # hardcoding VID/PID. ACTION=="add|change" covers both udevadm trigger
      # (nixos-rebuild switch) and resume-from-sleep events.
      # ENV{DEVTYPE}=="usb_device" is required: udevadm verify rejects bare
      # DEVTYPE==.
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{bDeviceClass}=="e0", ATTR{bDeviceSubClass}=="01", ATTR{bDeviceProtocol}=="01", TEST=="power/control", ATTR{power/control}="on"
      '';

      environment.systemPackages = lib.mkAfter [ pkgs.bluetui ];
    };
}
