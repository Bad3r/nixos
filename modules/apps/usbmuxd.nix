/*
  Package: usbmuxd
  Description: USB multiplexing daemon that services connections to iOS devices.
  Homepage: https://libimobiledevice.org/
  Documentation: https://github.com/libimobiledevice/usbmuxd#readme
  Repository: https://github.com/libimobiledevice/usbmuxd

  Summary:
    * Multiplexes TCP-like connections to iPhones and iPads over USB and brokers the pairing records used by lockdownd clients.
    * Owns the /var/run/usbmuxd socket that every libimobiledevice tool, ifuse mount, and the gvfs AFC backend connect through.

  Options:
    services.usbmuxd.extended.enable: Run the daemon and install udev rules that grant it access to Apple USB devices (vendor 05ac).
    services.usbmuxd.extended.package: Select the usbmuxd package; nixpkgs ships a git snapshot because upstream has tagged no release since 2020.

  Notes:
    * Headless daemon with no user-facing CLI; it starts at boot via multi-user.target and udev is triggered on activation so an already-plugged device is detected without replugging.
    * Required by the libimobiledevice, ifuse, and gvfs AFC paths; iPhone USB tethering also depends on it for the trust handshake.
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
