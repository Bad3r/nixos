/*
  Package: procs
  Description: Modern replacement for ps written in Rust.
  Homepage: https://github.com/dalance/procs
  Documentation: https://github.com/dalance/procs#readme
  Repository: https://github.com/dalance/procs

  Summary:
    * Lists processes in a colored table with TCP and UDP ports, read and write throughput, and Docker container names.
    * Supports keyword search, tree view, and watch mode.
*/
_:
let
  ProcsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.procs.extended;
    in
    {
      options.programs.procs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable procs.";
        };

        package = lib.mkPackageOption pkgs "procs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.procs = ProcsModule;
}
