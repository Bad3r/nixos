/*
  Package: hdparm
  Description: Linux utility for querying and setting ATA/SATA drive parameters.
  Homepage: https://sourceforge.net/projects/hdparm/
  Documentation: https://linux.die.net/man/8/hdparm
  Repository: https://github.com/stormogulen/hdparm (mirror)

  Summary:
    * Retrieves disk information (geometry, SMART-like stats) and controls power management, caching, and acoustic parameters.
    * Useful for benchmarking (`-tT`), setting spin-down timers, and enabling features like write caching or DMA.

  Options:
    -I <device>: Display detailed drive identification, including firmware and feature support.
    -tT <device>: Perform cached and buffered read timing tests.
    -S <value>: Configure standby (spin-down) timeout.
    -B <value>: Set Advanced Power Management level (0-255).
    -y/-Y/-Z <device>: Put the drive into standby, sleep, or sleep mode (requires caution).

  Example Usage:
    * `hdparm -I /dev/sda` -- Inspect drive capabilities and feature set.
    * `hdparm -tT /dev/nvme0n1` -- Benchmark sequential read performance for an NVMe device.
    * `hdparm -S 120 /dev/sdb` -- Spin down a drive after 10 minutes of inactivity (120 x 5 seconds).

  Notes:
    * `disk` group members run this without `sudo` through a capability wrapper carrying CAP_SYS_ADMIN and CAP_SYS_RAWIO.
    * The wrapper covers the whole binary, so destructive flags (`--security-erase`, `--trim-sector-ranges`, `--make-bad-sector`) also lose the sudo prompt.
*/
_:
let
  HdparmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hdparm.extended;
    in
    {
      options.programs.hdparm.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hdparm.";
        };

        package = lib.mkPackageOption pkgs "hdparm" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # ata_sas_scsi_ioctl() requires CAP_SYS_ADMIN and CAP_SYS_RAWIO together
        # for HDIO_DRIVE_CMD / HDIO_DRIVE_TASK, so -I and the other identify
        # paths return EACCES for a plain `disk` member.
        security.wrappers.hdparm = {
          source = "${cfg.package}/bin/hdparm";
          capabilities = "cap_sys_admin,cap_sys_rawio+ep";
          owner = "root";
          group = "disk";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.hdparm = HdparmModule;
}
