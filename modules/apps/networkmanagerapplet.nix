/*
  Package: networkmanagerapplet
  Description: GTK tray applet for controlling NetworkManager connections.
  Homepage: https://wiki.gnome.org/Projects/NetworkManager
  Documentation: https://developer.gnome.org/NetworkManager/stable/applet.html
  Repository: https://gitlab.gnome.org/GNOME/network-manager-applet

  Summary:
    * Provides a system tray indicator to manage Wi-Fi, wired, VPN, and mobile broadband connections with password storage and notifications.
    * Integrates 802.1x, VPN plug-ins, WWAN modems, and connection editing via `nm-connection-editor`.

  Options:
    --indicator: Enable Ayatana indicator for Unity-based desktops.
*/
_:
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
          description = "Whether to enable networkmanagerapplet.";
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
