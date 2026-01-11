/*
  Package: psmisc
  Description: Utilities that use the /proc filesystem for process management tasks.
  Homepage: https://gitlab.com/psmisc/psmisc
  Documentation: https://gitlab.com/psmisc/psmisc/-/wikis/home
  Repository: https://gitlab.com/psmisc/psmisc

  Summary:
    * Supplies tools like `pstree`, `fuser`, and `killall` for diagnosing and controlling running processes.
    * Assists administrators with identifying resource conflicts, open descriptors, and process hierarchies.

  Options:
    -p: Add process IDs to the `pstree -p` output for precise inspection.
    -v: Print verbose ownership and access details via `fuser -v <path>`.
    -r <pattern>: Enable regular-expression matching when issuing `killall -r`.
*/
_:
let
  PsmiscModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.psmisc.extended;
    in
    {
      options.programs.psmisc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable psmisc.";
        };

        package = lib.mkPackageOption pkgs "psmisc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.psmisc = PsmiscModule;
}
