/*
  Package: tcpdump
  Description: Network sniffer.
  Homepage: https://www.tcpdump.org/
  Documentation: https://www.tcpdump.org/

  Summary:
    * Captures and decodes packets from live interfaces or saved capture files.
    * Supports Berkeley Packet Filter expressions, capture rotation, and raw pcap output.

  Options:
    -i interface: Capture packets on a specific network interface.
    -c count: Stop after processing a fixed number of packets.
    -r file: Read packets from an existing capture file instead of a live interface.
    -w file: Write raw packets to a capture file for later analysis.
    -s snaplen: Limit how many bytes of each packet are captured.
*/
_:
let
  TcpdumpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tcpdump.extended;
    in
    {
      options.programs.tcpdump.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tcpdump.";
        };

        package = lib.mkPackageOption pkgs "tcpdump" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tcpdump = TcpdumpModule;
}
