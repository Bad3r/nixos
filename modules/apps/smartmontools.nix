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
    * `smartctl -a /dev/sda` -- Review detailed health metrics and error logs.
    * `smartctl -a /dev/nvme0n1` -- Read the NVMe SMART/health, error and self-test logs.
    * `smartctl -t long /dev/sda` -- Initiate an extended self-test (run in background).
    * Edit `/etc/smartd.conf` to schedule weekly tests and email alerts via `smartd`.

  Notes:
    * `disk` group members run `smartctl` without `sudo` through a capability wrapper carrying CAP_SYS_ADMIN and CAP_SYS_RAWIO.
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

        # Two separate kernel gates sit in front of SMART data: NVMe admin
        # passthrough checks CAP_SYS_ADMIN, and the SG_IO command filter that
        # ATA-over-SAT reads go through checks CAP_SYS_RAWIO.
        security.wrappers.smartctl = {
          source = "${cfg.package}/bin/smartctl";
          capabilities = "cap_sys_admin,cap_sys_rawio+ep";
          owner = "root";
          group = "disk";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.smartmontools = SmartmontoolsModule;
}
