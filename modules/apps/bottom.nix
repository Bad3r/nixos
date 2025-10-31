/*
  Package: bottom
  Description: Cross-platform TUI system monitor with charts for CPU, memory, disks, processes, and network usage.
  Homepage: https://github.com/ClementTsang/bottom
  Documentation: https://github.com/ClementTsang/bottom#readme
  Repository: https://github.com/ClementTsang/bottom

  Summary:
    * Provides command-line dashboards similar to htop/btop with customizable layouts, visual charts, and filtering.
    * Ships the `btm` binary supporting mouse interaction, process control, and exportable theming for both terminals and remote sessions.

  Options:
    btm: Launch the interactive dashboard (alias `bottom`).
    btm -b: Start in basic mode without graphs for low-bandwidth terminals.
    btm --config <file>: Load a specific configuration file overriding defaults.

  Example Usage:
    * `btm` — Open the full TUI system monitor with charts and process controls.
    * `btm -b -U 2` — Run in basic mode, updating every two seconds for lightweight monitoring.
    * `btm --config ~/.config/bottom/bottom.toml` — Apply a custom layout and theme.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  BottomModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bottom.extended;
    in
    {
      options.programs.bottom.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable bottom.";
        };

        package = lib.mkPackageOption pkgs "bottom" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bottom = BottomModule;
}
