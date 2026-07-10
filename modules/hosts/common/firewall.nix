# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallDnsInterfaces
#     Interfaces allowed to serve DNS/DHCP (UDP 53/67, TCP 53).
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  body =
    { hostName, lib, ... }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
      dnsInterfaces = hostFlags.firewallDnsInterfaces or [ ];
      extraTcpPortRanges = hostFlags.firewallExtraTcpPortRanges or [ ];
    in
    {
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          9999 # Stash default port
        ];
        allowedTCPPortRanges = extraTcpPortRanges;
        interfaces = {
          tailscale0.allowedTCPPorts = [ 22 ];
        }
        // lib.genAttrs dnsInterfaces (_: {
          allowedUDPPorts = [
            53
            67
          ];
          allowedTCPPorts = [ 53 ];
        });
        # Allow SSH from local network (10.0.0.0/8)
        extraCommands = ''
          iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept
        '';
        extraStopCommands = ''
          iptables -D nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept || true
        '';
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
