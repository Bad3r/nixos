# WARP troubleshooting

`warp-svc` logs to `journalctl -u cloudflare-warp.service`; `warp-cli` talks to it over its local socket without sudo.

## The switch warns that enrollment is disabled

Cause: `secrets/cloudflare-warp.yaml` is absent from the checkout, or the host's registry entry has `sopsRuntimeReady = false`.
Diagnostic: `ls secrets/cloudflare-warp.yaml` and `grep sopsRuntimeReady modules/<host>/policy.nix`.
Fix: `git submodule update --init secrets`, or install the age identity per [host secrets and handoff](../../guides/host-onboarding-secrets.md).

## Registration missing after the switch

Cause: `warp-svc` did not load `mdm.xml`, or the token is not in the Service Auth policy.
Diagnostic: `journalctl -u cloudflare-warp.service | grep -i -E 'policy|mdm|register|registration|auth'`; `Unable to read local policy file` followed by `Service token credentials not configured: missing organization` means the file did not load, and `warp-cli --accept-tos registration show` then reports `Account type: Free`.
Fix: for a load failure, read the next section; an authorization error in the log means the token id is absent from `hosts-service-auth` on the `Warp Login App`.

## warp-svc logs Too many levels of symbolic links

Cause: a symlink sits at `/var/lib/cloudflare-warp/mdm.xml`, and `warp-svc` opens its policy file without following symlinks, so the deployment is ignored and the client can only hold a Free consumer registration.
Diagnostic: `sudo ls -l /var/lib/cloudflare-warp/mdm.xml`; the unit's own view is `sudo nsenter -t "$(systemctl show -p MainPID --value cloudflare-warp.service)" -m cat /var/lib/cloudflare-warp/mdm.xml`.
Fix: `sudo rm /var/lib/cloudflare-warp/mdm.xml`, `warp-cli --accept-tos registration delete`, then `sudo systemctl restart cloudflare-warp.service`, which recreates the path as the bind mount of the sops render.

## resolvectl shows no DNS server on CloudflareWARP

Cause: `warp-svc` rejects the systemd 261 version string when it probes systemd-resolved, so it writes `/etc/resolv.conf` itself instead of configuring the tunnel link.
Diagnostic: `journalctl -u cloudflare-warp.service | grep 'file-based DNS'` shows the fallback, and `resolvectl dns` and `resolvectl domain` show `127.0.2.2 127.0.2.3` and `~.` under `Global`.
A domain listed on a link routes the names under it to that link's servers instead, past Gateway.
Fix: none while `Global` carries them, since in `warp` mode the module routes every lookup there; an empty `Global` means the host is not enrolled or runs `tunnelonly`.

## Name resolution fails in warp mode

Cause: systemd-resolved sends every name to the client's DNS proxy, so nothing resolves while `warp-svc` is not serving it, such as during a restart.
Diagnostic: `ss -lnu 'sport = :53'` lists no `127.0.2.2` or `127.0.2.3` socket, and `warp-cli --accept-tos status` shows the client state.
Fix: bring the client back per the sections above; to resolve without it, for example to fetch a recovery switch, `sudo resolvectl domain eth0 '~.'` lets songbird's uplink servers answer beside the proxy until `sudo resolvectl domain eth0 ''`.

## Status stays Disconnected after boot

Cause: a manual `warp-cli disconnect` holds until the next boot, or another tunnel owns the default route.
Diagnostic: `warp-cli --accept-tos status` and `nmcli -t -f NAME,TYPE con show --active`.
Fix: `warp-cli --accept-tos connect`, after `nmcli con down "<ProtonVPN connection>"` when ProtonVPN is up.

## warp-svc reports an IPv6 error

Cause: both hosts boot with `ipv6.disable=1`, and the client assigns an IPv6 address to its interface.
Diagnostic: `journalctl -u cloudflare-warp.service | grep -i -E 'ipv6|inet6|address family'`.
Fix: none on the host, since the kernel parameter stays; report the log lines and change the Cloudflare side instead.

## Peers cannot reach the host over the Mesh

Cause: the split-tunnel exclude list still covers `100.96.0.0/12`, Cloudflare Mesh is off for client devices, or the app is off on the host.
Diagnostic: `warp-cli --accept-tos settings`, `sudo iptables -S nixos-fw | grep CloudflareWARP`, and `nc -vz <meshIp> 22` from a peer.
Fix: replace the exclude entry with `100.64.0.0/11` and `100.112.0.0/12` on the profile, turn on Cloudflare Mesh for client devices, and check the host's `apps-enable.nix` override.

## A `<host>.warp` alias or Mesh address is unreachable

Cause: the [Cloudflare Mesh client devices](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-mesh/client-devices/) page requires the Traffic and DNS mode for Mesh connectivity and rules out DNS-only mode.
That page does not name Traffic-only mode either way, and tpnix's device profile runs Traffic-only mode (`warp_tunnel_only` through the API).
Diagnostic: `warp-cli --accept-tos settings` on tpnix reports its mode; compare it with the `nixos-tpnix` device profile, whose API mode is `warp_tunnel_only`.
Fix: switch tpnix's device profile mode and its `serviceMode` in `modules/tpnix/cloudflare-warp.nix` to `warp`, then retest.
`warp` mode replaces tpnix's NetworkManager dnsmasq resolver.
The private host mappings from `modules/hosts/common/private-dns-hosts.nix` need a follow-up, for example a Gateway local domain fallback, before this fallback becomes permanent.

## ping to a Mesh address times out while SSH works

Cause: the ICMP proxy is off under Traffic policies, Traffic settings in the dashboard.
Diagnostic: `nc -vz <meshIp> 22` succeeds and `ping -c 1 <meshIp>` does not.
Fix: turn on the ICMP proxy next to TCP and UDP under Traffic policies, Traffic settings in the dashboard.

## Private hostnames stop resolving on tpnix

Cause: the host runs in `warp` mode, so WARP replaced NetworkManager's dnsmasq as the resolver.
Diagnostic: `warp-cli --accept-tos settings` and `cat /etc/resolv.conf`.
Fix: set `serviceMode = "tunnelonly"` in `modules/tpnix/cloudflare-warp.nix` and `warp_tunnel_only` on the `nixos-tpnix` profile, then switch.

## The device profile does not apply

Cause: warp-svc 2026.7.1343.0 can keep a changed profile's previous settings past Cloudflare's ten-minute propagation window, or the match names the token instead of its id.
Diagnostic: `warp-cli --accept-tos settings` prints the profile id and the exclude list; compare both with the dashboard.
Fix: `sudo systemctl restart cloudflare-warp.service`; correct the profile's match expression when the id differs.
