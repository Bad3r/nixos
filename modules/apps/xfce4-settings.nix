/*
  Package: xfce4-settings
  Description: Xfce desktop settings manager providing unified dialogs for keyboard, appearance, display, and more.
  Homepage: https://docs.xfce.org/xfce/xfce4-settings/start
  Documentation: https://docs.xfce.org/xfce/xfce4-settings/usage
  Repository: https://gitlab.xfce.org/xfce/xfce4-settings

  Summary:
    * Launches the Xfce settings manager with modules for appearance, keyboard, mouse, display, window manager, and accessibility controls.
    * Includes helper tools like `xfce4-display-settings`, `xfce4-appearance-settings`, and `xfce4-mime-settings` for direct access.

  Options:
    xfce4-settings-manager: Open the main settings hub.
    xfce4-appearance-settings: Configure themes, icons, fonts.
    xfce4-display-settings: Manage display layout and resolution.
    xfce4-mime-settings: Adjust default applications for MIME types.

  Example Usage:
    * `xfce4-settings-manager` — Launch the unified settings interface for Xfce.
    * `xfce4-display-settings --minimal` — Quickly adjust monitors via minimal dialog.
    * `xfce4-keyboard-settings` — Configure keyboard layouts and shortcuts.
*/
_:
let
  Xfce4SettingsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."xfce4-settings".extended;
    in
    {
      options.programs."xfce4-settings".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Xfce4 settings manager.";
        };

        package = lib.mkPackageOption pkgs "xfce4-settings" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."xfce4-settings" = Xfce4SettingsModule;
}
