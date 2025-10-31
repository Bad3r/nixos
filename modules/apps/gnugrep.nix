/*
  Package: gnugrep
  Description: GNU implementation of grep for regular expression text search.
  Homepage: https://www.gnu.org/software/grep/
  Documentation: https://www.gnu.org/software/grep/manual/
  Repository: https://git.savannah.gnu.org/cgit/grep.git

  Summary:
    * Searches files and streams using basic, extended, or Perl-compatible regular expressions.
    * Offers color highlighting, recursive search, and binary safeguards for scripting workflows.

  Options:
    -R <pattern> <path>: Recursively search directories for matches.
    -E <pattern> <file>: Enable extended regular expressions.
    --color=auto <pattern> <file>: Highlight matches when writing to a terminal.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  GnugrepModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gnugrep.extended;
    in
    {
      options.programs.gnugrep.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable gnugrep.";
        };

        package = lib.mkPackageOption pkgs "gnugrep" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gnugrep = GnugrepModule;
}
