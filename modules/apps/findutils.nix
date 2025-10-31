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
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.findutils.extended;
  FindutilsModule = {
    options.programs.findutils.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable findutils.";
      };

      package = lib.mkPackageOption pkgs "findutils" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.findutils = FindutilsModule;
}
