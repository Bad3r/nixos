{ lib, ... }:
let
  # The default route on these hosts is an IPv4-only ProtonVPN WireGuard tunnel
  # that sinks every IPv6 destination into its ipv6leakintrf0 blackhole. With
  # IPv6 left on, resolvers still hand out AAAA records, so Nix substituter
  # fetches and Tailscale open IPv6 sockets that never complete the handshake
  # and stall until connect-timeout. Disabling IPv6 keeps only reachable IPv4
  # addresses in play.
  #
  # enableIPv6 = false only writes net.ipv6.conf.{all,default}.disable_ipv6,
  # which an interface reads once at creation. NetworkManager then writes
  # disable_ipv6 = 0 back onto every interface it activates with an ipv6.method
  # other than "disabled", so wifi0 and eth0 held a global address and an RA
  # default route while the all/default keys still read 1; tailscale0, whose
  # profile does say "disabled", was the only managed interface left at 1.
  # Those profiles are imperative state outside this repo, so the kernel
  # parameter is what keeps the runtime equal to this declaration: it returns
  # from inet6_init() before registering AF_INET6, leaving no
  # /proc/sys/net/ipv6 for NetworkManager or anything else to flip back.
  body = {
    networking.enableIPv6 = lib.mkDefault false;
    boot.kernelParams = [ "ipv6.disable=1" ];
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
