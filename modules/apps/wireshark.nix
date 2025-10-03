/*
  Package: wireshark
  Description: Network protocol analyzer with graphical and CLI interfaces for deep packet inspection.
  Homepage: https://www.wireshark.org/
  Documentation: https://www.wireshark.org/docs/
  Repository: https://gitlab.com/wireshark/wireshark

  Summary:
    * Captures and dissects network traffic with support for hundreds of protocols and display filters.
    * Includes `tshark` CLI, capture file analysis, and decryption helpers for many protocols.

  Options:
    wireshark: Launch the graphical interface for live capture and analysis.
    tshark -i <iface>: Perform command-line captures and parsing.
    dumpcap -i <iface> -w file.pcapng: Capture packets with minimal overhead.

  Example Usage:
    * `wireshark` — Inspect live traffic; ensure membership in the `wireshark` group for capture rights.
    * `tshark -Y "http.request" -r capture.pcapng` — Filter HTTP requests from a saved capture.
    * `dumpcap -i eth0 -b duration:300 -w /tmp/trace` — Rotate captures every five minutes for long-running monitoring.
*/

{
  flake.nixosModules.apps.wireshark =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wireshark ];
    };

}
