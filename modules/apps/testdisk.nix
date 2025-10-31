/*
  Package: testdisk
  Description: Data recovery suite featuring TestDisk (partition recovery) and PhotoRec (file carving).
  Homepage: https://www.cgsecurity.org/wiki/TestDisk
  Documentation: https://www.cgsecurity.org/wiki/TestDisk_Step_By_Step
  Repository: https://github.com/cgsecurity/testdisk

  Summary:
    * Recovers lost partitions, rebuilds partition tables, and repairs boot sectors on FAT/NTFS/ext filesystems.
    * Includes PhotoRec for recovering deleted files by signature, supporting numerous formats from damaged or formatted media.

  Options:
    testdisk: Interactive ncurses interface for analyzing disks and recovering partitions.
    photorec: File recovery tool focusing on carving files by signatures.
    testdisk /log: Enable logging to `testdisk.log` for troubleshooting.
    photorec /d <dir>: Set output directory for recovered files.

  Example Usage:
    * `sudo testdisk` — Launch interactive partition recovery with guided steps.
    * `sudo photorec /log /d ~/recovered` — Recover files from a damaged disk to a specific directory while logging.
    * Use TestDisk to rebuild an NTFS boot sector when partitions become unbootable.
*/
_:
let
  TestdiskModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.testdisk.extended;
    in
    {
      options.programs.testdisk.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable testdisk.";
        };

        package = lib.mkPackageOption pkgs "testdisk" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.testdisk = TestdiskModule;
}
