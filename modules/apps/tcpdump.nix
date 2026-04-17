/*
  Package: tcpdump
  Description: Network sniffer.
  Homepage: https://www.tcpdump.org/
  Documentation: https://www.tcpdump.org/
  Repository: https://github.com/the-tcpdump-group/tcpdump

  Summary:
    * Captures and decodes packets from live interfaces or saved capture files.
    * Supports Berkeley Packet Filter expressions, capture rotation, and raw pcap output.

  Options:
    -i interface: Capture packets on a specific network interface.
    -c count: Stop after processing a fixed number of packets.
    -r file: Read packets from an existing capture file instead of a live interface.
    -w file: Write raw packets to a capture file for later analysis.
    -s snaplen: Limit how many bytes of each packet are captured.

  Notes:
    * Installs a capability wrapper so `wheel` users can capture without invoking `sudo`.
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

        security.wrappers.tcpdump = {
          source = "${cfg.package}/bin/tcpdump";
          capabilities = "cap_net_raw,cap_net_admin+eip";
          owner = "root";
          group = "wheel";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.tcpdump = TcpdumpModule;
}
