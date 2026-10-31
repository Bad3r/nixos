/*
  Package: nix-output-monitor
  Description: Enhanced interface for streaming and summarizing Nix command output.
  Homepage: https://github.com/maralorn/nix-output-monitor
  Documentation: https://github.com/maralorn/nix-output-monitor#readme
  Repository: https://code.maralorn.de/maralorn/nix-output-monitor

  Summary:
    * Wraps Nix builds to group logs by derivation, highlight failures, and provide concise status dashboards.
    * Shows build progress and elapsed timing.

  Options:
    --json: Parse Nix `internal-json` log output.
*/
_:
let
  NixOutputMonitorModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nix-output-monitor".extended;
    in
    {
      options.programs.nix-output-monitor.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-output-monitor.";
        };

        package = lib.mkPackageOption pkgs "nix-output-monitor" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-output-monitor = NixOutputMonitorModule;
}
