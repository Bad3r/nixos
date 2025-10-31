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
_:
let
  WiresharkModule =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      cfg = config.programs.wireshark.extended;
      owner = metaOwner.username or (throw "Wireshark module: expected metaOwner.username to be defined");
    in
    {
      options.programs.wireshark.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable wireshark.";
        };

        package = lib.mkPackageOption pkgs "wireshark" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # Create wireshark group for packet capture permissions
        users.groups.wireshark = { };

        # Add owner to wireshark group
        users.users.${owner}.extraGroups = lib.mkAfter [ "wireshark" ];
      };
    };
in
{
  flake.nixosModules.apps.wireshark = WiresharkModule;
}
