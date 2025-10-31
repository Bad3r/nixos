/*
  Package: diffutils
  Description: GNU utilities for comparing files and directories.
  Homepage: https://www.gnu.org/software/diffutils/
  Documentation: https://www.gnu.org/software/diffutils/manual/diffutils.html
  Repository: https://git.savannah.gnu.org/cgit/diffutils.git

  Summary:
    * Delivers `diff`, `cmp`, `sdiff`, and `diff3` for textual and binary comparison workflows.
    * Generates unified, context, or side-by-side output suitable for code review and patch creation.

  Options:
    -u <old> <new>: Produce unified diffs commonly consumed by patch and review tools.
    -r <dir1> <dir2>: Recursively compare directory trees.
    --color=auto <old> <new>: Highlight differences when writing to a terminal.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  DiffutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.diffutils.extended;
    in
    {
      options.programs.diffutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable diffutils.";
        };

        package = lib.mkPackageOption pkgs "diffutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.diffutils = DiffutilsModule;
}
