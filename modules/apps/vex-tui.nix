/*
  Package: vex-tui
  Description: Terminal-based Excel and CSV viewer and editor.
  Homepage: https://github.com/CodeOne45/vex-tui
  Documentation: https://github.com/CodeOne45/vex-tui#usage
  Repository: https://github.com/CodeOne45/vex-tui

  Summary:
    * Opens Excel and CSV files in the terminal with delimiter detection and multi-sheet navigation.
    * Supports filtering, sorting, profiling, formula-aware editing, and chart export for tabular data.

  Options:
    -t, --theme <name>: Start with a named color theme.
    -d, --delimiter <char>: Set the CSV delimiter, using `\t` or `tab` for tabs.
    --version: Print version information.
    --help, -h: Show usage, themes, examples, and keyboard shortcuts.

  Notes:
    * The package is named `vex-tui`, but the installed binary is `vex`.
    * `csv-vex-tui` and `xls-vex-tui` are shell aliases for `vex`.
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
