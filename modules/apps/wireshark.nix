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
    * `wireshark` -- Inspect live traffic; `wheel` users can capture through the capability-wrapped `dumpcap`.
    * `tshark -Y "http.request" -r capture.pcapng` -- Filter HTTP requests from a saved capture.
    * `dumpcap -i eth0 -b duration:300 -w /tmp/trace` -- Rotate captures every five minutes for long-running monitoring.

  Notes:
    * Creates a compatibility `wireshark` group for tooling and policies that still expect it, while packet capture remains wheel-gated in this repo.
*/
_:
let
  WiresharkModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
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
          description = "Whether to enable wireshark.";
        };

        package = lib.mkPackageOption pkgs "wireshark" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        users.groups.wireshark = { };
        users.users.${owner}.extraGroups = lib.mkAfter [ "wireshark" ];

        security.wrappers.dumpcap = {
          source = "${cfg.package}/bin/dumpcap";
          capabilities = "cap_net_raw,cap_net_admin+ep";
          owner = "root";
          group = "wheel";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.wireshark = WiresharkModule;
}
