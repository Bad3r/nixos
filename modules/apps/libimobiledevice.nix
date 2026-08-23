/*
  Package: libimobiledevice
  Description: Library and CLI suite speaking Apple's native USB protocols to iOS devices.
  Homepage: https://libimobiledevice.org/
  Documentation: https://libimobiledevice.org/docs/libimobiledevice/latest/
  Repository: https://github.com/libimobiledevice/libimobiledevice

  Summary:
    * Talks lockdownd and its services (AFC, house_arrest, mobilebackup2, syslog_relay) over usbmuxd without jailbreaking.
    * Ships the idevice* tools used for pairing, device info, full and encrypted backups, crash reports, and developer mode.

  Options:
    idevicepair pair: Establish trust with a connected device; run again after accepting the on-device dialog.
    ideviceinfo: Print device identity, iOS version, and lockdown properties.
    idevicebackup2 backup --full <dir>: Create a full backup; "encryption on" first enables encrypted backups.
    idevicebackup2 restore <dir>: Restore a previously created backup; --system --settings overwrites device settings and reboots unless --no-reboot is passed.
    afcclient: Interactive AFC shell for the media filesystem; --documents <appid> targets an app sandbox.
    idevicesyslog: Stream the device syslog.

  Notes:
    * Every tool needs the usbmuxd daemon; the module asserts the service is enabled so the dependency fails at eval instead of at runtime.
    * 1.4.0 (2025-10) is the first upstream release since 1.3.0 (2020); re-pair once after a major iOS upgrade when lockdownd rejects the stored record.
*/
_:
let
  LibimobiledeviceModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.libimobiledevice.extended;
    in
    {
      options.programs.libimobiledevice.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable libimobiledevice.";
        };

        package = lib.mkPackageOption pkgs "libimobiledevice" { };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.services.usbmuxd.enable;
            message = "programs.libimobiledevice.extended.enable requires the usbmuxd daemon; enable services.usbmuxd.extended.enable.";
          }
        ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.libimobiledevice = LibimobiledeviceModule;
}
