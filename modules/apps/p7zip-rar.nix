/*
  Package: p7zip-rar
  Description: 7-Zip command-line utilities with proprietary RAR decompression plugin enabled.
  Homepage: https://p7zip.sourceforge.net/
  Documentation: https://linux.die.net/man/1/7z
  Repository: https://sourceforge.net/projects/p7zip/

  Summary:
    * Extends 7-Zip (`7z`, `7za`) with the unrar plugin to extract RAR archives in addition to 7z, zip, tar, and other formats.
    * Useful when handling mixed archive types on systems relying on 7-Zip CLI rather than graphical tools.

  Options:
    7z x archive.rar: Extract RAR archives with full path support.
    7z a archive.7z files: Create high-compression 7z archives.
    7z l archive.rar: List contents without extracting.
    7z t archive.7z: Test archive integrity.

  Example Usage:
    * `7z x downloads/file.rar` — Extract a RAR archive using the p7zip-rar plugin.
    * `7z a backup.7z Documents` — Compress a directory into a 7z archive.
    * `7z l backup.7z` — Inspect the contents of an archive before extracting.
*/
_:
let
  P7zipRarModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."p7zip-rar".extended;
    in
    {
      options.programs.p7zip-rar.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable p7zip-rar.";
        };

        package = lib.mkPackageOption pkgs "p7zip-rar" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "p7zip" ];

  flake.nixosModules.apps.p7zip-rar = P7zipRarModule;
}
