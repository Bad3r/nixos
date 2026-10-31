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
    testdisk /log: Enable logging to `testdisk.log` for troubleshooting.
    photorec /d <dir>: Set output directory for recovered files.
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
          description = "Whether to enable testdisk.";
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
