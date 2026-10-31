/*
  Package: maestral-gui
  Description: Qt6 GUI frontend for Maestral Dropbox client.
  Homepage: https://maestral.app
  Documentation: https://maestral.readthedocs.io
  Repository: https://github.com/samschott/maestral-qt

  Summary:
    * Native Qt6 system tray application for managing Dropbox sync on Linux.
    * Provides visual sync status, selective sync configuration, and account management.

  Notes:
    * Requires the maestral CLI.
    * Launch command: `maestral_qt`.
*/
_:
let
  MaestralGuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."maestral-gui".extended;
    in
    {
      options.programs."maestral-gui".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable maestral-gui.";
        };

        package = lib.mkPackageOption pkgs "maestral-gui" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."maestral-gui" = MaestralGuiModule;
}
