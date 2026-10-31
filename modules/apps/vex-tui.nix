/*
  Package: vex-tui
  Description: Terminal-based Excel and CSV viewer and editor.
  Homepage: https://github.com/CodeOne45/vex-tui
  Documentation: https://github.com/CodeOne45/vex-tui#usage
  Repository: https://github.com/CodeOne45/vex-tui

  Summary:
    * Opens Excel and CSV files in the terminal with delimiter detection and multi-sheet navigation.
    * Filters, sorts, profiles, and edits tabular data, and exports charts.

  Options:
    -t, --theme <name>: Start with a named color theme.
    -d, --delimiter <char>: Set the CSV delimiter.
    --version: Print version information.
    --help, -h: Show usage and keyboard shortcuts.

  Notes:
    * The binary is `vex`.
*/
_:
let
  VexTuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.vex-tui.extended;
    in
    {
      options.programs.vex-tui.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vex-tui.";
        };

        package = lib.mkPackageOption pkgs "vex-tui" { };
      };

      config = lib.mkIf cfg.enable {
        environment.shellAliases = {
          csv-vex-tui = "vex";
          xls-vex-tui = "vex";
        };

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.vex-tui = VexTuiModule;
}
