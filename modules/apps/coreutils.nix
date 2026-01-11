/*
  Package: coreutils
  Description: GNU Core Utilities collection of essential file, text, and shell programs.
  Homepage: https://www.gnu.org/software/coreutils/
  Documentation: https://www.gnu.org/software/coreutils/manual/coreutils.html
  Repository: https://git.savannah.gnu.org/cgit/coreutils.git

  Summary:
    * Provides canonical implementations of commands such as `ls`, `cp`, `mv`, `chmod`, and `cat`.
    * Extends POSIX behavior with GNU-specific options, localization, and robust internationalization support.

  Options:
    --help: Append to any coreutils command (e.g., `ls --help`) to display detailed usage information.
    --version: Print version and licensing details for the invoked coreutils program.
    --preserve-root: Protect `/` from recursive removal when running `rm --preserve-root -rf /`.
*/
_:
let
  CoreutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.coreutils.extended;
    in
    {
      options.programs.coreutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable coreutils.";
        };

        package = lib.mkPackageOption pkgs "coreutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.coreutils = CoreutilsModule;
}
