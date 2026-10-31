/*
  Package: hdparm
  Description: Linux utility for querying and setting ATA/SATA drive parameters.
  Homepage: https://sourceforge.net/projects/hdparm/
  Documentation: https://linux.die.net/man/8/hdparm
  Repository: nil

  Summary:
    * Retrieves disk information (geometry, SMART-like stats) and controls power management, caching, and acoustic parameters.
    * Useful for benchmarking (`-tT`), setting spin-down timers, and enabling features like write caching or DMA.

  Options:
    -I <device>: Display detailed drive identification, including firmware and feature support.
    -tT <device>: Perform cached and buffered read timing tests.
    -S <value>: Configure standby (spin-down) timeout.
    -B <value>: Set Advanced Power Management level (1-255).
    -y, -Y <device>: Put the drive into standby or sleep mode.

  Notes:
    * Device queries need `sudo`.
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
      };
    };
in
{
  flake.nixosModules.apps.hdparm = HdparmModule;
}
