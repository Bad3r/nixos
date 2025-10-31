/*
  Package: lsof
  Description: Utility for listing open files, sockets, and devices on Unix-like systems.
  Homepage: https://github.com/lsof-org/lsof
  Documentation: https://github.com/lsof-org/lsof#readme
  Repository: https://github.com/lsof-org/lsof

  Summary:
    * Shows which processes hold file descriptors, enabling diagnosis of locks, leaks, and port conflicts.
    * Supports filtering by command, user, network endpoint, or mount point.

  Options:
    -i :<port>: Identify processes listening on or connecting to a specific TCP or UDP port.
    +D <path>: Recursively enumerate open files beneath a directory tree.
    -p <pid>: Restrict output to descriptors opened by a given process ID.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  LsofModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lsof.extended;
    in
    {
      options.programs.lsof.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable lsof.";
        };

        package = lib.mkPackageOption pkgs "lsof" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lsof = LsofModule;
}
