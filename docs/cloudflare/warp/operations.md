# WARP Operations

Runtime verification, coexistence checks, and troubleshooting after
`nixos-rebuild switch` on an enrolled host.

## Verify the daemon and enrollment

```bash
systemctl status cloudflare-warp.service          # warp-svc running
systemctl status cloudflare-warp-connect.service  # oneshot succeeded (active/exited)
ls -l /var/lib/cloudflare-warp/mdm.xml            # 0600 root:root, present
warp-cli registration show                        # enrolled into <team> (non_identity@<team>...)
warp-cli status                                   # Connected
```

The `cloudflare-warp-connect` oneshot polls the daemon for up to 30 seconds
before it issues `warp-cli connect`, so on a fresh boot the unit can take that
long to reach `active (exited)`.

Confirm WARP is carrying traffic:

```bash
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E '^warp='   # warp=on
```

## Zero Trust dashboard checks

- The device appears under Team & Resources > Devices.
- Gateway DNS/HTTP logs show this device's queries (confirms Full mode + Gateway
  DNS).

## Coexistence checks

- `tailscale status` is still reachable (confirms the `100.64.0.0/10`
  split-tunnel exclude).
- Internal / `.local` names resolve (confirms Local Domain Fallback).

## Reapplying managed config

The `cloudflare-warp.service` carries a `restartTriggers` hash of the non-secret
mdm fields (`organization`, `serviceMode`, `autoConnect`, `switchLocked`).
Changing any of them and rebuilding restarts `warp-svc`, which re-reads
`mdm.xml`. Rotating the service token (the sops secret) re-renders the file on
the next activation.

## Troubleshooting

- **Enrollment fails / device shows then drops.** The service token likely lacks
  device-enrollment permission. Add a Service Auth rule referencing the token
  (Deployment, step 3). Collect a diagnostics bundle: `sudo warp-diag`.
- **mdm.xml missing at boot (race).** `mdm.xml` is installed by an `ExecStartPre`
  that copies the sops-rendered template. The template is rendered during
  activation, before `multi-user.target`, and `warp-svc` has `Restart=always`, so
  a transient miss self-heals. If a cold-boot race is observed, order
  `cloudflare-warp.service` after the sops template unit (add `after`/`wants` on
  the sops setup unit) and rebuild.
- **No connectivity with strict rp_filter.** The module sets
  `networking.firewall.checkReversePath = "loose"` by default. If a host firewall
  module forces `strict`, the `CloudflareWARP` interface drops return traffic.
- **DNS resolver conflict.** Full mode (`warp` / `1dot1`) makes WARP the DNS
  resolver. Do not also enable `services.dnscrypt-proxy` (or import
  `flake.nixosModules.workstation`); the module warns if you do.
- **General diagnostics.** `sudo warp-diag` writes a zip with logs and settings;
  `sudo warp-diag feedback` is the same bundle framed for a support ticket.
