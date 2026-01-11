/*
  Package: nix-output-monitor
  Description: Enhanced interface for streaming and summarizing Nix command output.
  Homepage: https://github.com/maralorn/nix-output-monitor
  Documentation: https://github.com/maralorn/nix-output-monitor#readme
  Repository: https://github.com/maralorn/nix-output-monitor

  Summary:
    * Wraps Nix builds to group logs by derivation, highlight failures, and provide concise status dashboards.
    * Offers progress metadata, elapsed timing, and optional JSON summaries for automation pipelines.

  Options:
    --json: Emit machine-readable summaries alongside the TUI when wrapping `nix build`.
    --keep-going: Continue building remaining derivations after a failure, mirroring `nix build --keep-going`.
    --max-concurrent-jobs <n>: Restrict the number of builds running in parallel for resource control.
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
