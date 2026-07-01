_:
let
  # The default route on these hosts is an IPv4-only ProtonVPN WireGuard tunnel
  # that sinks every IPv6 destination into its ipv6leakintrf0 blackhole. With
  # IPv6 left on, resolvers still hand out AAAA records, so Nix substituter
  # fetches and Tailscale open IPv6 sockets that never complete the handshake
  # and stall until connect-timeout. Disabling IPv6 keeps only reachable IPv4
  # addresses in play. enableIPv6 = false sets
  # net.ipv6.conf.{all,default}.disable_ipv6 = true.
  body = {
    networking.enableIPv6 = false;
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
