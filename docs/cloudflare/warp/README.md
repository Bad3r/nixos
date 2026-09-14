# Cloudflare WARP on the fleet

`modules/apps/cloudflare-warp.nix` enrolls a host into the Zero Trust team with a per-host Access service token and runs `warp-svc` as a managed client.
No browser login happens on the host: sops-nix renders the team name, the token, and the mode into the managed deployment file `mdm.xml` from `secrets/cloudflare-warp.yaml`.

## Behavior

- `programs.cloudflare-warp.extended.enable` opts a host in through its `apps-enable.nix` override; the common baseline leaves it off.
- The host enrolls only when its registry entry sets `sopsRuntimeReady` and the secret file exists; otherwise the switch warns and installs only `warp-cli` and `warp-diag` for diagnosis.
- The rendered `mdm.xml` stays under `/run/secrets`, a tmpfs, and reaches the WARP state directory as a read-only bind mount, so the token never lands on disk.
  `warp-svc` opens its policy file without following symlinks, which rules out a link into `/run/secrets`.
- A changed token or mode restarts `warp-svc` through the template's restart hook.
- The client starts Connected after install and after every boot; a manual `warp-cli disconnect` holds until the next boot.
- The upstream inbound UDP opening stays off, since the client only dials out over MASQUE.

## Mode per host

tpnix stays on `tunnelonly` because NetworkManager's dnsmasq serves the private-host mappings from `modules/hosts/common/private-dns-hosts.nix`, which Gateway DNS would replace.
The mode is set in `modules/<host>/cloudflare-warp.nix`, and the host's device profile in the dashboard carries the same mode, matched on the host's service token.
Cloudflare documents Mesh for the Traffic and DNS mode, so tpnix's Traffic-only mode is checked at rollout (see [troubleshooting.md](troubleshooting.md)).

## Reaching hosts over Cloudflare Mesh

Enrolled devices get an address in `100.96.0.0/12` and reach each other directly.
The shared firewall in `modules/hosts/common/firewall.nix` opens SSH and the host's declared developer port ranges on the `CloudflareWARP` interface, and nothing else.
A host records its address as `meshIp` in `modules/<host>/policy.nix`; every other host then pins the host key for that address, and every other host that runs WARP renders `~/.ssh/hosts/<host>.warp`.
Evaluation rejects a `meshIp` outside `100.96.0.0/12`, since the alias and the pin would name an address the tunnel never carries.
`ping` between devices needs the ICMP proxy, enabled under Traffic policies, Traffic settings in the dashboard.

## Coexistence

- ProtonVPN stays installed for manual use, with its NetworkManager autoconnect turned off before the first switch as [deployment.md](deployment.md) shows, since two default-route tunnels cannot share a host.
  Bring ProtonVPN down before relying on WARP, and the other way round.
- Tailscale is off in the common baseline; a host that opts back in keeps the `tailscale0` firewall rule and the `primary` alias mechanism in `modules/apps/tailscale.nix`.
- IPv6 is disabled at the kernel on both hosts, so WARP carries IPv4 only here.

## Secrets

`secrets/cloudflare-warp.yaml` holds `organization` once and one section per host named after its `networking.hostName`; the `.example` file beside it in the secrets repository shows the shape.
The team name identifies the tenant and this repository is public, which is why it lives in the encrypted file as well.

## Pages

- [Deployment](deployment.md): Cloudflare objects, the sops payload, host enrollment, recording `meshIp`, token rotation.
- [Troubleshooting](troubleshooting.md): symptoms with cause, diagnostic, and fix.

Source: [Cloudflare One client on Linux](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/).
