/*
  Package: blueberry
  Description: Linux Mint’s GTK bluetooth manager for controlling BlueZ outside GNOME.
  Homepage: https://github.com/linuxmint/blueberry
  Documentation: https://github.com/linuxmint/blueberry#readme
  Repository: https://github.com/linuxmint/blueberry

  Summary:
    * Provides a simple tray app and control panel for pairing devices, toggling adapters, and managing Bluetooth audio routing.
    * Wraps GNOME Bluetooth tooling so Cinnamon, Xfce, and other desktops can reuse the same BlueZ stack.

  Options:
    blueberry: Launch the GTK control panel to pair, trust, and remove Bluetooth devices.
    blueberry-tray: Start the background tray indicator that exposes quick toggles and notifications.

  Example Usage:
    * `blueberry` -- Open the Bluetooth settings panel for pairing and device management.
    * `blueberry-tray` -- Launch the tray icon to monitor adapters and expose quick toggles for discovery and visibility.
    * `mkdir -p ~/.config/autostart {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} cp /etc/xdg/autostart/blueberry-tray.desktop ~/.config/autostart/` -- Enable the tray indicator automatically for your user session.
*/
_:
let
  BlueberryModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.blueberry.extended;
    in
    {
      options.programs.blueberry.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable blueberry.";
        };

        package = lib.mkPackageOption pkgs "blueberry" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.blueberry = BlueberryModule;
}
