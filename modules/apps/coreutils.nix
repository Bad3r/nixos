/*
  Package: coreutils
  Description: GNU Core Utilities collection of essential file, text, and shell programs.
  Homepage: https://www.gnu.org/software/coreutils/
  Documentation: https://www.gnu.org/software/coreutils/manual/coreutils.html
  Repository: https://cgit.git.savannah.gnu.org/cgit/coreutils.git

  Summary:
    * Provides core commands such as `ls`, `cp`, `mv`, `chmod`, and `cat`.
    * Extends POSIX behavior with GNU-specific options.

  Options:
    --help: Show usage for any coreutils command.
    --version: Print the command's version.
    --preserve-root: Refuse to operate recursively on `/`.
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
