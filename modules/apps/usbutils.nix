/*
  Package: usbutils
  Description: Utilities for listing and interrogating USB devices.
  Homepage: https://github.com/gregkh/usbutils
  Documentation: https://github.com/gregkh/usbutils#readme
  Repository: https://github.com/gregkh/usbutils

  Summary:
    * Provides `lsusb`, `usb-devices`, and related tools for inspecting USB buses and device descriptors.
    * Uses the usb.ids database to resolve vendor and product names when troubleshooting hardware.

  Options:
    -v: Show verbose descriptor details for attached USB devices via `lsusb -v`.
    -t: Display the USB topology as a tree using `lsusb -t`.
    -D <device>: Dump descriptors for a specific device path with `lsusb -D /dev/bus/usb/...`.
*/
_:
let
  UsbutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.usbutils.extended;
    in
    {
      options.programs.usbutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable usbutils.";
        };

        package = lib.mkPackageOption pkgs "usbutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.usbutils = UsbutilsModule;
}
