/*
  Package: s-tui
  Description: Terminal-based CPU stress and monitoring utility.
  Homepage: https://amanusk.github.io/s-tui/
  Documentation: https://amanusk.github.io/s-tui/
  Repository: https://github.com/amanusk/s-tui

  Summary:
    * Monitors CPU temperature, utilization, frequency, and power from a terminal UI.
    * Highlights performance dips from thermal throttling and can stress the CPU from the same interface.

  Options:
    -d, --debug: Output debug logs to `_s-tui.log`.
    -c, --csv: Save sampled stats to a CSV file.
    -t, --terminal: Print a single line of stats without launching the TUI.
    -j, --json: Print a single line of stats as JSON.
    -nm, --no-mouse: Disable mouse handling for TTY systems.
    -tt, --t_thresh: Set the high-temperature threshold.

  Notes:
    * The nixpkgs package propagates `stress`; no separate module wiring is required.
*/
_:
let
  STuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."s-tui".extended;
    in
    {
      options.programs."s-tui".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable s-tui.";
        };

        package = lib.mkPackageOption pkgs "s-tui" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."s-tui" = STuiModule;
}
