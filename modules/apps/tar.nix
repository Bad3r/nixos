/*
  Package: tar
  Description: GNU implementation of the tar archiver for creating and extracting tape archives.
  Homepage: https://www.gnu.org/software/tar/
  Documentation: https://www.gnu.org/software/tar/manual/
  Repository: https://git.savannah.gnu.org/git/tar.git

  Summary:
    * Creates, lists, updates, and extracts tar archives across local or streamed destinations.
    * Supports compression and incremental backups through options that integrate gzip, bzip2, xz, and snapshot metadata.

  Options:
    -c: Create a new archive from the specified files or directories.
    -x: Extract files from an archive, preserving permissions and timestamps.
    -t: List archive contents without extracting them.
    --gzip: Compress or decompress archives using gzip during create or extract operations.
    --listed-incremental=FILE: Maintain snapshot state for incremental backups using the provided metadata file.
*/
_:
let
  TarModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tar.extended;
    in
    {
      options.programs.tar.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tar (GNU tar).";
        };

        package = lib.mkPackageOption pkgs "gnutar" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tar = TarModule;
}
