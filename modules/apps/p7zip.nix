/*
  Package: p7zip
  Description: Port of 7-Zip command-line utilities for POSIX systems, supporting the 7z archive format and others.
  Homepage: https://p7zip.sourceforge.net/
  Documentation: https://linux.die.net/man/1/7z
  Repository: https://sourceforge.net/projects/p7zip/

  Summary:
    * Provides `7z`, `7za`, and `7zr` utilities for creating and extracting various archive formats with high compression ratios.
    * Supports scripting-friendly command options for backup, packaging, encryption, and testing archives.

  Options:
    7z a <archive.7z> <files>: Add files to a new or existing archive.
    7z x <archive>: Extract with full paths.
    7z e <archive>: Extract to current directory without preserving paths.
    7z t <archive>: Test archive integrity.
    7z l <archive>: List contents.

  Example Usage:
    * `7z a project.7z src/` — Compress a source directory into a 7z archive.
    * `7z x project.7z -o./output` — Extract to a specific directory.
    * `7z t backup.7z` — Verify that an archive is not corrupted.
*/

{
  flake.nixosModules.apps.p7zip =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.p7zip ];
    };

}
