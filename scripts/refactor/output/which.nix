/*
  Package: which
  Description: Utility that locates executable files in the user PATH.
  Homepage: https://savannah.gnu.org/projects/which/
  Documentation: https://man.archlinux.org/man/which.1
  Repository: https://git.savannah.gnu.org/cgit/which.git

  Summary:
    * Resolves the full path to commands as they would be executed in the current environment.
    * Supports shell alias awareness, duplicates detection, and compatibility with POSIX shells.

  Options:
    --all: Show every matching executable on `$PATH`, not just the first (`which --all <command>`).
    --read-alias <shell>: Expand aliases when resolving commands, useful for interactive shells.
    --read-functions: Detect shell functions in addition to binaries when using `which`.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.which.extended;
  WhichModule = {
    options.programs.which.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable which.";
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
