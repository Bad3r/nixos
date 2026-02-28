/*
  Package: dwarfs
  Description: High-compression read-only filesystem tools for mount, extract, and integrity workflows.
  Homepage: https://github.com/mhx/dwarfs
  Documentation: https://github.com/mhx/dwarfs#readme
  Repository: https://github.com/mhx/dwarfs

  Summary:
    * Provides `dwarfs`, `dwarfsextract`, and `dwarfsck` commands used by jc141 launchers for archive mount and extraction flows.
    * Delivers compact game payload storage while preserving fast read paths and integrity verification tooling.
    * Used by default in `programs.steam.extended.extraTools` for Steam mod/runtime compatibility workflows.

  Options:
    dwarfs <image> <mountpoint>: Mount a `.dwarfs` archive through FUSE.
    dwarfsextract -i <image> -o <dir>: Extract an archive into a writable directory tree.
    dwarfsck --check-integrity -i <image>: Validate archive integrity before launch or distribution.
*/
_:
let
  DwarfsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dwarfs.extended;
    in
    {
      options.programs.dwarfs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dwarfs.";
        };

        package = lib.mkPackageOption pkgs "dwarfs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dwarfs = DwarfsModule;
}
