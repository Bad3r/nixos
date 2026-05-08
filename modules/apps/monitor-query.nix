/*
  Package: monitor-query
  Description: Shell helper library that reports active i3 monitor geometry,
    sourced by scratchpad scripts to compute placement/size.
  Repository: https://github.com/Bad3r/nixos

  Notes:
    * Generated via writeText from lib/shell/monitor-query.nix and exposed by
      modules/custom-overlays/monitor-query.nix.
    * Sourced by modules/apps/i3wm/scratchpad.nix as a path
      (`. "${pkgs.monitor-query}"`); it is a single file, not a derivation
      with bin/share/ outputs, so it is never added to
      `environment.systemPackages`. The app module exists solely to provide
      the option that gates the overlay registration.
*/
_:
let
  MonitorQueryModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."monitor-query".extended;
    in
    {
      options.programs."monitor-query".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the monitor-query shell library overlay.";
        };

        package = lib.mkPackageOption pkgs "monitor-query" { };
      };

      # No environment.systemPackages: monitor-query is a writeText output
      # consumed via `pkgs.monitor-query` at script-eval time, not installed
      # into the user environment.
      config = lib.mkIf cfg.enable { };
    };
in
{
  flake.nixosModules.apps."monitor-query" = MonitorQueryModule;
}
