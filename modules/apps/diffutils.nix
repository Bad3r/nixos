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
  flake.nixosModules.apps.diffutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.diffutils ];
    };
}
