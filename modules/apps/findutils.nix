/*
  Package: findutils
  Description: GNU tools for searching filesystems and matching files.
  Homepage: https://www.gnu.org/software/findutils/
  Documentation: https://www.gnu.org/software/findutils/manual/find.html
  Repository: https://git.savannah.gnu.org/cgit/findutils.git

  Summary:
    * Ships `find`, `xargs`, `locate`, and `updatedb` for flexible filesystem queries and automation.
    * Supports rich predicates, pruning, and command execution over matched files.

  Options:
    -name '*.nix': Match files by name using glob patterns when invoking `find`.
    -mtime -1: Filter entries modified within the last day.
    -exec <command> {} +: Batch matched files into command invocations for better performance.
*/

{
  flake.nixosModules.apps.findutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.findutils ];
    };
}
