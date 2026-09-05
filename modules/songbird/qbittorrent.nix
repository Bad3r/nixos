_:
let
  # qBittorrent's incoming-peer port, mapped TCP+UDP by Proton VPN's NAT-PMP
  # forwarding onto the tunnel (the app always names it proton0). Proton picks
  # the port per session, so a new port moves here and into Session\Port together.
  port = 48845;
in
{
  configurations.nixos.songbird.module = {
    networking.firewall.interfaces.proton0 = {
      allowedTCPPorts = [ port ];
      allowedUDPPorts = [ port ];
    };
  };
}
