/*
  Package: workloads
  Description: Command line for the declared workloads of a host and its live sbx sandboxes.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/blob/main/docs/networking/workload-names.md

  Summary:
    * Lists the names the host resolves for declared guests and services, with their addresses and networks.
    * Lists the resolver records each workload network serves its guests, and live sandboxes when sbx is installed.

  Options:
    names: Print declared names, resolver records, and live sandboxes.
    --json: Print results and errors as JSON.

  Notes:
    * Reads /etc/workloads/names.json, which modules/workloads/sharing/names.nix writes.
    * Without sbx on PATH, `names` reports `"sandboxes": null` and says so on stderr.
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
