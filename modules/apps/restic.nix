/*
  Package: restic
  Description: Backup program that is fast, efficient and secure.
  Homepage: https://restic.net/
  Documentation: https://restic.readthedocs.io/
  Repository: https://github.com/restic/restic

  Summary:
    * Stores encrypted, deduplicated snapshots of files and directories in a repository on a local disk, SFTP, a REST server, S3-compatible storage, or an rclone backend.
    * Restores, mounts, and compares snapshots, forgets them by retention policy, and verifies repository integrity.

  Options:
    init: Initialize a new repository.
    backup: Create a new backup of files and/or directories.
    snapshots: List all snapshots.
    restore: Extract the data from a snapshot.
    forget --prune: Remove snapshots, then prune the data only those snapshots referenced.
    -r, --repo: Repository to back up to or restore from (default: $RESTIC_REPOSITORY).
*/
_:
let
  ResticModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.restic.extended;
    in
    {
      options.programs.restic.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable restic.";
        };

        package = lib.mkPackageOption pkgs "restic" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.restic = ResticModule;
}
