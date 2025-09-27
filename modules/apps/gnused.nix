/*
  Package: gnused
  Description: GNU stream editor for non-interactive text transformations.
  Homepage: https://www.gnu.org/software/sed/
  Documentation: https://www.gnu.org/software/sed/manual/sed.html
  Repository: https://git.savannah.gnu.org/cgit/sed.git

  Summary:
    * Applies scripted substitutions, insertions, and deletions to text streams and files.
    * Supports in-place editing, extended regular expressions, and multi-line pattern spaces.

  Options:
    -e 's/old/new/': Perform one-off substitutions on stdin or files.
    -n '1,10p': Print only selected line ranges without default output.
    -i.bak 's/foo/bar/': Edit files in place while writing backups with the specified suffix.
*/

{
  flake.nixosModules.apps.gnused =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnused ];
    };
}
