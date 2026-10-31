/*
  Package: aircrack-ng
  Description: Wireless network security auditing suite for capturing and cracking Wi-Fi keys.
  Homepage: https://www.aircrack-ng.org/
  Documentation: https://www.aircrack-ng.org/doku.php?id=newdoc
  Repository: https://github.com/aircrack-ng/aircrack-ng

  Summary:
    * Provides tools for packet capture, replay attacks, deauthentication, and key cracking on 802.11 networks.
    * Supports WPA/WPA2-PSK auditing with GPU acceleration via external tools.

  Options:
    aireplay-ng --deauth <count> -a <bssid> <iface>: Send deauthentication frames.

  Notes:
    * Capture and injection tools need `sudo`.
*/
_:
let
  AircrackNgModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."aircrack-ng".extended;
    in
    {
      options.programs.aircrack-ng.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable aircrack-ng.";
        };

        package = lib.mkPackageOption pkgs "aircrack-ng" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.aircrack-ng = AircrackNgModule;
}
