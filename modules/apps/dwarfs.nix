/*
  Package: dwarfs
  Description: High-compression read-only filesystem tools for mount, extract, and integrity workflows.
  Homepage: https://github.com/mhx/dwarfs
  Documentation: https://github.com/mhx/dwarfs#readme
  Repository: https://github.com/mhx/dwarfs

  Summary:
    * Mounts, extracts, and checks `.dwarfs` images with `dwarfs`, `dwarfsextract`, and `dwarfsck`.

  Options:
    dwarfsextract -i <image> -o <dir>: Extract an archive into a writable directory tree.
    dwarfsck --check-integrity -i <image>: Validate archive integrity.
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
