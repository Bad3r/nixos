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

{
  flake.nixosModules.apps.testdisk =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.testdisk ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.testdisk ];
    };
}
