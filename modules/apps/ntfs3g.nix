/*
  Package: ntfs-3g
  Description: FUSE-based read-write NTFS driver and utilities for Linux.
  Homepage: https://www.tuxera.com/community/open-source-ntfs-3g/
  Documentation: https://linux.die.net/man/8/ntfs-3g
  Repository: https://github.com/tuxera/ntfs-3g

  Summary:
    * Provides user-space driver `ntfs-3g` for mounting NTFS partitions with full read/write support.
    * Includes `ntfsfix`, `ntfsinfo`, and other utilities for basic NTFS maintenance and diagnostics.

  Options:
    ntfs-3g <device> <mountpoint>: Mount an NTFS partition via FUSE.
    -o uid=<uid>,gid=<gid>: Set ownership of mounted files.
    -o permissions: Enable POSIX permission emulation.
    ntfsfix <device>: Perform basic consistency checks and fix common NTFS errors.

  Example Usage:
    * `sudo ntfs-3g /dev/sdb1 /mnt/windows` — Mount a Windows partition with read/write access.
    * `sudo ntfsfix /dev/sdb1` — Fix simple corruption before mounting.
    * `sudo ntfs-3g -o uid=$(id -u),gid=$(id -g) /dev/sdb2 ~/win-share` — Mount with current user ownership.
*/
_:
let
  Ntfs3gModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ntfs3g.extended;
    in
    {
      options.programs.ntfs3g.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ntfs3g.";
        };

        package = lib.mkPackageOption pkgs "ntfs3g" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ntfs3g = Ntfs3gModule;
}
