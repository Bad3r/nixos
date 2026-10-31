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
    idevicepair pair: Pair with a connected device; run again after accepting the on-device dialog.
    idevicebackup2 backup --full <dir>: Create a full backup in an existing <dir>.
    idevicebackup2 -i: Prompt for backup passwords.
    idevicebackup2 restore <dir>: Restore a previously created backup.

  Notes:
    * Every tool needs the usbmuxd daemon.
    * `idevicebackup2 restore` reboots the device unless `--no-reboot` is given; `--settings` overwrites device settings.
    * Re-pair after a major iOS upgrade if lockdownd rejects the stored pairing.
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
