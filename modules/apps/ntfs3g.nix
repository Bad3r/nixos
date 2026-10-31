/*
  Package: ntfs3g
  Description: FUSE-based read-write NTFS driver and utilities for Linux.
  Homepage: https://www.tuxera.com/community/open-source-ntfs-3g/
  Documentation: https://linux.die.net/man/8/ntfs-3g
  Repository: https://github.com/tuxera/ntfs-3g

  Summary:
    * Provides user-space driver `ntfs-3g` for mounting NTFS partitions with full read/write support.
    * Includes `ntfsfix`, `ntfsinfo`, and other utilities for basic NTFS maintenance and diagnostics.

  Options:
    -o uid=<uid>,gid=<gid>: Set ownership of mounted files.
    -o permissions: Enable POSIX permission emulation.
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
