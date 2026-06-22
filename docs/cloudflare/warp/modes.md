# Choosing a WARP mode

Choose the WARP mode before changing host configuration. The mode controls which
Zero Trust features reach the device because each mode combines DNS, tunneling,
and posture collection differently.

This repository enables `Gateway with WARP` by default for enrolled hosts. That
maps to `service_mode = "warp"` in `mdm.xml` and keeps DNS filtering, HTTP
filtering, device posture, and domain-based split tunneling active.

## Compare the client modes

| Dashboard mode                           | `service_mode` | `warp-cli mode` | Traffic handled           | Gateway DNS | HTTP filtering | Posture |
| ---------------------------------------- | -------------- | --------------- | ------------------------- | ----------- | -------------- | ------- |
| Gateway with WARP                        | `warp`         | `warp+doh`      | All traffic and DNS       | Yes         | Yes            | Yes     |
| Gateway with DoH                         | `1dot1`        | `doh`           | DNS only                  | Yes         | No             | No      |
| Secure Web Gateway without DNS filtering | `tunnelonly`   | `tunnel_only`   | All traffic, OS keeps DNS | No          | Yes            | Yes     |
| Proxy                                    | `proxy`        | `proxy`         | `127.0.0.1:40000` only    | No          | Yes            | No      |
| Device Information Only                  | `postureonly`  | n/a             | None                      | No          | No             | Yes     |

`warp-cli settings` reports the same modes as `WarpWithDnsOverHttps`,
`DnsOverHttps`, `TunnelOnly`, `WarpProxy`, and `PostureOnly`.

## Prefer full mode for enrolled hosts

Use `Gateway with WARP` unless a host must keep an independent DNS resolver.
Full mode makes WARP the system resolver, so Gateway DNS policies can block
malware, phishing, and content categories before a connection starts.

Full mode also preserves domain-based split tunneling because the client owns
resolution. Internal names still work when their suffixes are configured in
Local Domain Fallback.

Use `tunnelonly` only when Cloudflare cannot control DNS on the device. It keeps
the tunnel, HTTP filtering, network policies, and posture checks, but it removes
Gateway DNS filtering, DNS query logs, and domain-based split tunneling.

## Avoid local DNS resolver conflicts

Do not run a local resolver on `127.0.0.1:53` while using full mode. If a host
enables `services.dnscrypt-proxy` or imports a module that provides a competing
local resolver, switch WARP to `tunnelonly` or disable the local resolver.

The `tpnix` and `system76` hosts use NetworkManager with DHCP, and the unused
`flake.nixosModules.workstation` module owns the `services.dnscrypt-proxy`
definition. Full mode is the expected setting for the current enrolled hosts.

## Configure split tunnels

Configure split tunnels in the Zero Trust device profile. Exclude mode sends all
traffic through WARP except listed IPs and domains. Include mode sends only
listed IPs and domains through WARP.

Keep the default RFC1918 exclusions so local networks stay reachable. Also
exclude Tailscale's `100.64.0.0/10` range on hosts that use the tailnet.

`tunnelonly` and `postureonly` disable domain-based split tunneling. In those
modes, split only by IP or CIDR.

## References

- [WARP modes](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/configure-warp/warp-modes/)
- [Split tunnels](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/configure-warp/route-traffic/split-tunnels/)
- [Local Domain Fallback](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/configure-warp/route-traffic/local-domains/)
