/*
  Package: overskride
  Description: Bluetooth and Obex client that is straight to the point, DE/WM agnostic, and beautiful.
  Homepage: https://github.com/kaii-lb/overskride
  Documentation: https://github.com/kaii-lb/overskride/blob/main/README.md
  Repository: https://github.com/kaii-lb/overskride

  Summary:
    * GTK4/libadwaita front end for BlueZ that lists known and in-range devices, handles pair/connect/trust/block, and exposes adapter controls.
    * Sends and receives files over OBEX, supports multiple adapters, RSSI-based device sorting, and adapter renaming.

  Options:
    overskride: Launch the Bluetooth and Obex client window.

  Notes:
    * Requires the BlueZ daemon (`hardware.bluetooth.enable`); enable Bluetooth at the host level.
    * Pulls in gtk4 + libadwaita; intentional GUI dependency for non-GNOME desktops such as i3wm.
*/
_:
let
  OverskrideModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.overskride.extended;
    in
    {
      options.programs.overskride.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable overskride.";
        };

        package = lib.mkPackageOption pkgs "overskride" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.overskride = OverskrideModule;
}
