/*
  Package: patchutils
  Description: Utilities for inspecting, filtering, combining, and repairing patch files.
  Homepage: https://github.com/twaugh/patchutils
  Documentation: https://github.com/twaugh/patchutils#readme
  Repository: https://github.com/twaugh/patchutils

  Summary:
    * Supplies `filterdiff`, `lsdiff`, and `grepdiff` for selecting and inspecting patch contents.
    * Includes tools for combining incremental patches and repairing edited diffs.

  Options:
    filterdiff -i <pattern> <patch>: Extract changes to matching file paths.
*/
_:
let
  PatchutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.patchutils.extended;
    in
    {
      options.programs.patchutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable patchutils.";
        };

        package = lib.mkPackageOption pkgs "patchutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.patchutils = PatchutilsModule;
}
