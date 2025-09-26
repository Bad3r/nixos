/*
  Package: unrar
  Description: Proprietary command-line utility for extracting RAR archives.
  Homepage: https://www.rarlab.com/
  Documentation: https://www.rarlab.com/rar_add.htm
  Repository: https://www.rarlab.com/rar/unrarsrc-6.2.12.tar.gz (source releases)

  Summary:
    * Decompresses RAR and RAR5 archives, including multi-volume sets and encrypted archives (with password).
    * Supports testing archives, printing file lists, and extracting specific paths while preserving permissions.

  Options:
    unrar x archive.rar [dest]: Extract with full paths to destination directory.
    unrar e archive.rar: Extract files without recreating directory structure.
    unrar t archive.rar: Test archive integrity without extracting.
    unrar l archive.rar: List archive contents.
    -p<password>: Supply password for encrypted archives.

  Example Usage:
    * `unrar x files.part1.rar` — Extract a multi-part RAR archive.
    * `unrar l archive.rar` — Inspect contents before extracting.
    * `unrar x -ppassword secure.rar` — Extract an encrypted archive with the provided password.
*/

{
  flake.nixosModules.apps.unrar =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.unrar ];
    };

}
