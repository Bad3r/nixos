/*
  Package: gawk
  Description: GNU implementation of the Awk programming language for text processing.
  Homepage: https://www.gnu.org/software/gawk/
  Documentation: https://www.gnu.org/software/gawk/manual/
  Repository: https://git.savannah.gnu.org/cgit/gawk.git

  Summary:
    * Processes structured text streams with pattern-action rules, associative arrays, and math/string functions.
    * Extends traditional awk with networking, internationalization, and dynamic extension loading.

  Options:
    -f script.awk: Execute an Awk program from a file.
    -v NAME=value: Pass external variables into a script.
    --posix: Enable POSIX compatibility mode for portability.
*/

{
  flake.nixosModules.apps.gawk =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gawk ];
    };
}
