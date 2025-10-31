/*
  Package: sysstat
  Description: Collection of performance monitoring tools including `sar`, `iostat`, and `mpstat`.
  Homepage: https://github.com/sysstat/sysstat
  Documentation: https://sebastien.godard.pagesperso-orange.fr/man.html
  Repository: https://github.com/sysstat/sysstat

  Summary:
    * Captures historical CPU, memory, disk, and network metrics for capacity planning and troubleshooting.
    * Includes daemons and utilities for periodic data collection and interactive inspection.

  Options:
    -u 1 5: Report CPU utilization at one-second intervals via `sar -u`.
    -xz 5: Display extended disk I/O statistics every five seconds with `iostat -xz`.
    -P ALL 1: Show per-core CPU stats refreshed each second using `mpstat -P ALL`.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.sysstat.extended;
  SysstatModule = {
    options.programs.sysstat.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable sysstat.";
      };

      package = lib.mkPackageOption pkgs "sysstat" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.sysstat = SysstatModule;
}
