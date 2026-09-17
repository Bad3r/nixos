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
- In `warp` mode systemd-resolved sends every lookup to the client's local DNS proxy while the `CloudflareWARP` tunnel exists, and to the link servers once it is gone. That route is gated on `services.resolved.enable`: a host running `warp` mode with resolved off, as `modules/hosts/common/private-dns-hosts.nix` forces for a host with `privateDnsHostsSecretKeys`, has no `cloudflare-warp-dns.service` and resolves through the `/etc/resolv.conf` `warp-svc` writes instead.
- The upstream inbound UDP opening stays off, since the client only dials out over WireGuard or
  MASQUE.

## Mode per host

tpnix stays on `tunnelonly` because NetworkManager's dnsmasq serves the private-host mappings from `modules/hosts/common/private-dns-hosts.nix`, which Gateway DNS would replace.
The mode is set in `modules/<host>/cloudflare-warp.nix`, and the host's device profile in the dashboard carries the same mode, matched on the host's service token.
Cloudflare spells Traffic-only mode three ways: `tunnelonly` as the `service_mode` value in `mdm.xml`, `warp_tunnel_only` in the device-profile API, and `tunnel_only` in `warp-cli mode`.
tpnix's Traffic-only mode is checked at rollout because it leaves DNS with NetworkManager (see
[troubleshooting.md](troubleshooting.md)).

## Reaching hosts over Cloudflare Mesh

Enrolled devices get an account-assigned Mesh address and reach each other directly.
The shared firewall in `modules/hosts/common/firewall.nix` opens SSH and the host's declared developer port ranges on the `CloudflareWARP` interface.
Every device on Mesh is enrolled by the same owner as the hosts, so Mesh counts as a local network: a service opened on every interface, through `openFirewall` or the global `networking.firewall` port lists, answers on Mesh as it does on the LAN.
The interface is the scope: every device enrolled in the team reaches those ranges over Mesh, and only Gateway policies on the Cloudflare side narrow that.

A host with an address stored under `mesh.hosts.<host>` in the encrypted
`secrets/cloudflare-warp.yaml` sets `cloudflareWarpMeshAddressReady = true` in
`modules/<host>/policy.nix`.
On a host that runs WARP, sops-nix renders those values into `/etc/hosts` as `<host>.internal` entries.
`.internal` is reserved for private use, so public DNS never resolves a name missing from `/etc/hosts`.
The addresses remain out of the public source and the Nix store; they exist as plaintext only in
the deployed runtime file.
`modules/networking/ssh-hosts.nix` renders `~/.ssh/hosts/<host>.internal` without a build-time `HostName`,
and `modules/hosts/common/ssh-known-hosts.nix` pins that name to the fleet host key.
The `.internal` aliases select the dedicated 1Password-backed fleet SSH key, while every fleet host
authorizes that key and disables password and keyboard-interactive SSH authentication.
`github.com` selects the separate 1Password key used for Git signing and GitHub SSH authentication.
GitHub stores that same key in both roles, as [its documentation requires](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account).
The client does not forward the 1Password agent to the remote host.
The `/etc/hosts` entry gives NSS clients such as `ping`, `getent`, and SSH the same name without
sending `.internal` to Gateway or link DNS.
It is a host-local mapping rather than an authoritative DNS record, so direct DNS clients such as
`dig` do not use it and other enrolled devices do not inherit it.
Nix evaluation cannot inspect encrypted values, so the deployment runbook verifies the rendered
mapping and direct route after every address change.
`ping` between devices needs the ICMP proxy, enabled under Traffic policies, Traffic settings in the dashboard.
Cloudflare Mesh hostname routes are a different feature and do not work with WireGuard; these local
aliases continue to route directly to the recorded IPv4 Mesh addresses.

## Coexistence

- ProtonVPN stays installed for manual use, with its NetworkManager autoconnect turned off before the first switch as [deployment.md](deployment.md) shows, since two default-route tunnels cannot share a host.
  Bring ProtonVPN down before relying on WARP, and the other way round.
- Tailscale is off in the common baseline; a host that opts back in keeps the `tailscale0` firewall rule and the `primary` alias mechanism in `modules/apps/tailscale.nix`.
- IPv6 is disabled at the kernel on both hosts, so WARP carries IPv4 only here; the client can still log an IPv6 error against that disabled parameter (see [troubleshooting.md](troubleshooting.md)).

## Secrets

`secrets/cloudflare-warp.yaml` holds `organization`, `mesh.cidr`, each `mesh.hosts.<host>` address,
and one token section per host named after its `networking.hostName`; the `.example` file beside it
in the secrets repository shows the shape.
The team name, Mesh network values, and tokens remain encrypted in the repository.

## Pages

- [Deployment](deployment.md): Cloudflare objects, the sops payload, host enrollment, Mesh address changes, token rotation.
- [Troubleshooting](troubleshooting.md): symptoms with cause, diagnostic, and fix.

Source: [Cloudflare One client on Linux](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/).
