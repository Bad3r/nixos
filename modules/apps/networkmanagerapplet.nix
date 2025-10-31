/*
  Package: networkmanager-applet
  Description: GTK tray applet for controlling NetworkManager connections.
  Homepage: https://wiki.gnome.org/Projects/NetworkManager
  Documentation: https://developer.gnome.org/NetworkManager/stable/applet.html
  Repository: https://gitlab.gnome.org/GNOME/network-manager-applet

  Summary:
    * Provides a system tray indicator to manage Wi-Fi, wired, VPN, and mobile broadband connections with password storage and notifications.
    * Integrates 802.1x, VPN plug-ins, WWAN modems, and connection editing via `nm-connection-editor`.

  Options:
    nm-applet: Start the NetworkManager status icon in the system tray.
    --indicator: Enable Ayatana indicator for Unity-based desktops.
    nm-connection-editor: Launch the advanced connection configuration dialog.

  Example Usage:
    * `nm-applet --indicator {PRESERVED_DOCUMENTATION}` — Run the applet in the background on minimal desktops.
    * Click the tray icon to connect/disconnect Wi-Fi and VPN connections.
    * `nm-connection-editor` — Edit advanced connection settings such as IPv6, DNS, and security settings.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  NetworkmanagerappletModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.networkmanagerapplet.extended;
    in
    {
      options.programs.networkmanagerapplet.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable networkmanagerapplet.";
        };

        package = lib.mkPackageOption pkgs "networkmanagerapplet" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.networkmanagerapplet = NetworkmanagerappletModule;
}
