/*
  Package: workloads
  Description: Command line for the declared workloads of a host, its live sbx sandboxes, and runtime grants.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/blob/main/docs/networking/workload-names.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Lists the names the host resolves for declared guests and services, with their addresses and networks.
    * Lists the resolver records each workload network serves its guests, and live sandboxes when sbx is installed.
    * Opens, lists, and revokes TTL-bound grants through workload-grantd.

  Options:
    names: Print declared names, resolver records, and live sandboxes.
    grant <source> <target> [--ttl 30m]: Open a path from a sandbox or guest to a target.
    revoke <id> | --all <source>: Close grants and their connections.
    grants: List live grants.
    --json: Print results and errors as JSON.
*/
_:
let
  WorkloadsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.workloads.extended;
    in
    {
      options.programs.workloads.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the workloads command line.";
        };

        package = lib.mkPackageOption pkgs "workloads" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.workloads = WorkloadsModule;
}
