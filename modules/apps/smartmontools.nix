/*
  Package: smartmontools
  Description: Tools for monitoring and controlling storage devices via SMART (Self-Monitoring, Analysis and Reporting Technology).
  Homepage: https://www.smartmontools.org/
  Documentation: https://www.smartmontools.org/wiki/Documentation
  Repository: https://github.com/smartmontools/smartmontools

  Summary:
    * Provides `smartctl` for querying disk health, running self-tests, and enabling SMART features, plus the `smartd` daemon for scheduled monitoring and alerts.
    * Supports SATA, NVMe, SCSI, and USB-enclosed devices with extensive reporting of attributes and error logs.

  Options:
    smartctl -a /dev/sdX: Display all SMART information for a drive.
    smartctl -t short /dev/sdX: Start a short self-test.
    smartctl -H /dev/nvme0: Report overall health status.
    smartctl -v ID,FORMAT /dev/sdX: Select a vendor attribute display format.
    smartctl -F TYPE /dev/sdX: Apply a documented firmware-bug workaround.
    smartd.conf: Configure daemon monitoring intervals and notification methods.

  Example Usage:
    * `sudo smartctl -a /dev/sda` -- Review detailed health metrics and error logs.
    * `sudo smartctl -a /dev/nvme0n1` -- Read the NVMe SMART/health, error and self-test logs.
    * `sudo smartctl -t long /dev/sda` -- Initiate an extended self-test (run in background).
    * Edit `/etc/smartd.conf` to schedule weekly tests and email alerts via `smartd`.

  Notes:
    * Every device query needs `sudo` (docs/security/owner-storage-access.md).
*/
_:
let
  SmartmontoolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.smartmontools.extended;
    in
    {
      options.programs.smartmontools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable smartmontools.";
        };

        package = lib.mkPackageOption pkgs "smartmontools" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.smartmontools = SmartmontoolsModule;
}
