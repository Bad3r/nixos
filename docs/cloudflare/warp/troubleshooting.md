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

Cause: `warp-svc` rejects the systemd 261 version string when it probes systemd-resolved, so it writes `/etc/resolv.conf` itself instead of configuring resolved over D-Bus.
Diagnostic: `cat /etc/resolv.conf` names `127.0.2.2` and `127.0.2.3`, and `journalctl -u cloudflare-warp.service | grep 'file-based DNS'` shows the fallback.
Fix: none on the host; Gateway DNS applies to every glibc resolver client, while `resolvectl query` and other resolved clients keep using the link servers.

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

Cause: profile changes propagate within about ten minutes, and the match uses the token id, not the token name.
Diagnostic: `warp-cli --accept-tos settings` prints the profile id; compare it with the dashboard.
Fix: wait, then `sudo systemctl restart cloudflare-warp.service`; correct the profile's match expression when the id differs.
