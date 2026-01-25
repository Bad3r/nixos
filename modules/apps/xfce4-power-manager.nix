/*
  Package: xfce4-power-manager
  Description: Power management daemon and panel plugin for the Xfce desktop.
  Homepage: https://docs.xfce.org/xfce/xfce4-power-manager/start
  Documentation: https://docs.xfce.org/xfce/xfce4-power-manager/usage
  Repository: https://gitlab.xfce.org/xfce/xfce4-power-manager

  Summary:
    * Manages power profiles, battery notifications, brightness, and suspend/hibernate behavior within Xfce and other lightweight desktops.
    * Provides system tray indicators, keyboard brightness shortcuts, and integration with UPower/Logind for event handling.

  Options:
    xfce4-power-manager: Launch the daemon and tray icon.
    xfce4-power-manager-settings: Open the graphical settings dialog for configuring actions and display policies.
    Command-line flags: `--no-daemon`, `--restart` for controlling the daemon directly.

  Example Usage:
    * `xfce4-power-manager` -- Start the power management daemon (usually auto-started in Xfce sessions).
    * `xfce4-power-manager-settings` -- Configure battery thresholds, display blanking, and critical actions.
    * Use keyboard brightness keys; the daemon handles adjusting brightness and notifications.
*/
_:
let
  Xfce4PowerManagerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."xfce4-power-manager".extended;
    in
    {
      options.programs."xfce4-power-manager".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Xfce4 power manager.";
        };

        package = lib.mkPackageOption pkgs [ "xfce" "xfce4-power-manager" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."xfce4-power-manager" = Xfce4PowerManagerModule;
}
