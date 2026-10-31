/*
  Package: rsync
  Description: Fast, incremental file transfer and synchronization utility.
  Homepage: https://rsync.samba.org/
  Documentation: https://download.samba.org/pub/rsync/rsync.html
  Repository: https://github.com/RsyncProject/rsync

  Summary:
    * Synchronizes files locally or over SSH/remote shells with delta encoding and compression.
    * Supports include/exclude filters, partial transfers, bandwidth limits, and checksum-based verification.

  Options:
    rsync -avz <src> <dest>: Archive mode with compression for typical syncs.
    rsync --delete: Remove files at the destination that no longer exist at the source.
    rsync --bwlimit=<kbps>: Limit transfer bandwidth when sharing constrained links.
*/
_:
let
  RsyncModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rsync.extended;
    in
    {
      options.programs.rsync.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable rsync.";
        };

        package = lib.mkPackageOption pkgs "rsync" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.rsync = RsyncModule;
}
