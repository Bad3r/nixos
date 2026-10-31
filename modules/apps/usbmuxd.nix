/*
  Package: usbmuxd
  Description: USB multiplexing daemon that services connections to iOS devices.
  Homepage: https://libimobiledevice.org/
  Documentation: https://github.com/libimobiledevice/usbmuxd#readme
  Repository: https://github.com/libimobiledevice/usbmuxd

  Summary:
    * Multiplexes TCP-like connections to iPhones and iPads over USB and brokers the pairing records used by lockdownd clients.
    * Owns the /var/run/usbmuxd socket that every libimobiledevice tool, ifuse mount, and the gvfs AFC backend connect through.

  Notes:
    * Headless daemon with no user-facing CLI.
    * iPhone USB tethering depends on it.
*/
_:
let
  UsbmuxdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.usbmuxd.extended;
    in
    {
      options.services.usbmuxd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable usbmuxd.";
        };

        package = lib.mkPackageOption pkgs "usbmuxd" { };
      };

      config = lib.mkIf cfg.enable {
        services.usbmuxd = {
          enable = true;
          inherit (cfg) package;
        };
      };
    };
in
{
  flake.nixosModules.apps.usbmuxd = UsbmuxdModule;
}
