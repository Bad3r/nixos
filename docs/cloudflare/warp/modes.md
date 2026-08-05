# Choosing a WARP mode

Choose the WARP mode before changing host configuration. The mode controls which
Zero Trust features reach the device because each mode combines DNS, tunneling,
and posture collection differently.

System76 uses `Gateway with WARP`, which maps to `service_mode = "warp"` in
`mdm.xml` and keeps DNS filtering, HTTP filtering, device posture, and
domain-based split tunneling active. Tpnix uses `tunnelonly` because its local
NetworkManager dnsmasq service owns private-host resolution.

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

## Select full mode when no local resolver is active

Use `Gateway with WARP` unless a host must keep an independent DNS resolver.
Full mode makes WARP the system resolver, so Gateway DNS policies can block
malware, phishing, and content categories before a connection starts.

Full mode also preserves domain-based split tunneling because the client owns
resolution. Internal names still work when their suffixes are configured in
Local Domain Fallback.

Use `tunnelonly` only when Cloudflare cannot control DNS on the device. It keeps
the tunnel, HTTP filtering, network policies, and posture checks, but it removes
Gateway DNS filtering, DNS query logs, and domain-based split tunneling.

Tpnix intentionally uses `tunnelonly` so its SignalX private-host mappings stay
available through NetworkManager dnsmasq. Do not change it to `warp` unless those
mappings move to Zero Trust Local Domain Fallback first.

## Avoid local DNS resolver conflicts

Do not run a local resolver on `127.0.0.1:53` while using full mode. If a host
enables `services.dnscrypt-proxy` or imports a module that provides a competing
local resolver, switch WARP to `tunnelonly` or disable the local resolver.

The current host modules do not enable `services.dnscrypt-proxy`. The shared
private-DNS module selects NetworkManager dnsmasq only when the host declares
private DNS keys, its SOPS runtime is ready, and `secrets/<host>.yaml` exists.
`tpnix` currently meets those conditions for SignalX DNS, so inspect the
evaluated host DNS setting before selecting full mode. Tpnix therefore uses
`tunnelonly` and does not trigger the Full-mode resolver warning. Full mode is
appropriate for system76 because no competing local resolver is active there.

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
