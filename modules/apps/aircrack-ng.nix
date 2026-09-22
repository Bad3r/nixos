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
    airodump-ng <iface>: Capture wireless frames on a specified interface.
    aireplay-ng --deauth <count> -a <bssid> <iface>: Send deauthentication frames.
    aircrack-ng <capture.cap>: Attempt to recover keys from captured handshakes.

  Example Usage:
    * `airodump-ng wlan0mon` -- Collect handshakes and network details once interface is in monitor mode.
    * `aireplay-ng --deauth 10 -a <AP> -c <CLIENT> wlan0mon` -- Force a reconnect to capture WPA handshakes.
    * `aircrack-ng -w wordlist.txt handshake.cap` -- Crack a WPA2-PSK handshake using a wordlist.

  Notes:
    * No capability wrappers: every live-capture and injection binary here links aircrack-ng's Linux osdep backend, which shells out with the caller-supplied interface name on every card open (`lib/osdep/linux.c` `do_linux_open()`, an unconditional `system()` with no prior privilege drop), so a wrapper would hand that shell CAP_NET_RAW/CAP_NET_ADMIN through the interface argument (issue #475). Use `sudo` for `airbase-ng`, `aireplay-ng`, `airodump-ng`, `airserv-ng`, `airtun-ng`, `besside-ng`, `easside-ng`, `tkiptun-ng`, and `wesside-ng`.
    * `airmon-ng` is an upstream shell script and was never wrapped; monitor-mode setup already requires elevated setup.
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
