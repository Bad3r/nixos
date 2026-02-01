/*
  Package: czkawka-gui
  Description: GTK4 graphical interface for finding duplicate and unnecessary files.
  Homepage: https://github.com/qarmin/czkawka
  Documentation: https://github.com/qarmin/czkawka/blob/master/instructions/GUI.md
  Repository: https://github.com/qarmin/czkawka

  Summary:
    * Provides GTK4-based GUI for all czkawka scanning modes with visual result browsing.
    * Supports image previews, batch operations, and persistent settings.

  Notes:
    * Part of the czkawka package which includes both CLI and GUI binaries.
    * Also includes Krokiet, an experimental Slint-based GUI alternative.
    * If czkawka-cli is also enabled, both modules reference the same store path.
*/
_:
let
  CzkawkaGuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.czkawka-gui.extended;
    in
    {
      options.programs.czkawka-gui.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable czkawka-gui.";
        };

        package = lib.mkPackageOption pkgs "czkawka" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.czkawka-gui = CzkawkaGuiModule;
}
