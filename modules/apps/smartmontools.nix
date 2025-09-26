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
    smartd.conf: Configure daemon monitoring intervals and notification methods.

  Example Usage:
    * `sudo smartctl -a /dev/sda` — Review detailed health metrics and error logs.
    * `sudo smartctl -t long /dev/sda` — Initiate an extended self-test (run in background).
    * Edit `/etc/smartd.conf` to schedule weekly tests and email alerts via `smartd`.
*/

{
  flake.nixosModules.apps.smartmontools =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.smartmontools ];

      services.smartd = {
        enable = true;
        notifications = {
          x11.enable = true;
          wall.enable = true;
        };
      };
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.smartmontools ];

      services.smartd = {
        enable = true;
        notifications = {
          x11.enable = true;
          wall.enable = true;
        };
      };
    };
}
