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
_:
let
  GawkModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gawk.extended;
    in
    {
      options.programs.gawk.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable gawk.";
        };

        package = lib.mkPackageOption pkgs "gawk" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gawk = GawkModule;
}
