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
    * Requires maestral CLI for core functionality; this package provides the GUI layer.
    * Launches from system tray; use `maestral_qt` command or desktop entry.
    * Account linking can be completed through the GUI wizard.
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
