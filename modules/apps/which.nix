/*
  Package: which
  Description: Utility that locates executable files in the user PATH.
  Homepage: https://savannah.gnu.org/projects/which/
  Documentation: https://man.archlinux.org/man/which.1
  Repository: https://cgit.git.savannah.gnu.org/cgit/which.git

  Summary:
    * Prints the full path of the command the shell would run.

  Options:
    --all: Show every matching executable on `$PATH`, not just the first.
    --read-alias: Read shell aliases from stdin and report matches.
    --read-functions: Read shell functions from stdin and report matches.
*/
_:
let
  WhichModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.which.extended;
    in
    {
      options.programs.which.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable which.";
        };

        package = lib.mkPackageOption pkgs "which" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.which = WhichModule;
}
