# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallDnsInterfaces
#     Interfaces allowed to serve DNS/DHCP (UDP 53/67, TCP 53).
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  body =
    {
      hostName,
      config,
      lib,
      ...
    }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
      dnsInterfaces = hostFlags.firewallDnsInterfaces or [ ];
      extraTcpPortRanges = hostFlags.firewallExtraTcpPortRanges or [ ];
      # enp4s0, eno1, ens3, enx001122334455, wlp0s20f3; not eth0 or wlan0.
      predictableNames = lib.filter (n: lib.match "(en|wl)[posx].*" n != null) dnsInterfaces;
    in
    {
      # A name that matches no device is not an evaluation error on its own:
      # genAttrs below still emits an interfaces entry, so the opening silently
      # does nothing. Catch the one case that guarantees a dead name.
      assertions = [
        {
          assertion = config.networking.usePredictableInterfaceNames || predictableNames == [ ];
          message =
            "${hostName}: firewallDnsInterfaces has predictable interface names "
            + "(${lib.concatStringsSep ", " predictableNames}) but the host boots with "
            + "net.ifnames=0, so they match no device. Use the kernel name (eth0, wlan0) "
            + "read from `ip -br link` after the first boot on this configuration.";
        }
      ];

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
