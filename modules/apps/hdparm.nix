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
    -B <value>: Set Advanced Power Management level (0–255).
    -y/-Y/-Z <device>: Put the drive into standby, sleep, or sleep mode (requires caution).

  Example Usage:
    * `sudo hdparm -I /dev/sda` — Inspect drive capabilities and feature set.
    * `sudo hdparm -tT /dev/nvme0n1` — Benchmark sequential read performance for an NVMe device.
    * `sudo hdparm -S 120 /dev/sdb` — Spin down a drive after 10 minutes of inactivity (120 × 5 seconds).
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
          description = lib.mdDoc "Whether to enable hdparm.";
        };

        package = lib.mkPackageOption pkgs "hdparm" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.hdparm = HdparmModule;
}
