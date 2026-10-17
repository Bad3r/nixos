/*
  Package: zenity
  Description: Tool to display dialogs from the commandline and shell scripts.
  Homepage: https://gitlab.gnome.org/GNOME/zenity
  Documentation: zenity --help-all
  Repository: https://gitlab.gnome.org/GNOME/zenity

  Summary:
    * Displays graphical dialogs for shell scripts, including messages, prompts, and file selection.
    * Returns user input through standard output and dialog results through exit codes.

  Options:
    --info: Display an informational message.
    --question: Display a confirmation dialog.
    --entry: Prompt for text input.
    --file-selection: Open a file selection dialog.
    --progress: Display a progress dialog.
    --help-all: Show all supported options.
*/
_:
let
  ZenityModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zenity.extended;
    in
    {
      options.programs.zenity.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable zenity.";
        };

        package = lib.mkPackageOption pkgs "zenity" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.zenity = ZenityModule;
}
