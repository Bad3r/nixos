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

  Example Usage:
    * `rsync -avP /data/ user@host:/backup/` — Mirror a directory to a remote host via SSH.
    * `rsync -av --delete --exclude '.cache/' src/ dest/` — Maintain an exact replica while skipping cache files.
    * `rsync -avz --bwlimit=5000 files/ rsync://mirror.example.org/share/` — Upload to an rsync daemon with throttled bandwidth.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.rsync.extended;
  RsyncModule = {
    options.programs.rsync.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable rsync.";
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
