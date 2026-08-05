# WARP Operations

Runtime verification, coexistence checks, and troubleshooting after
`nixos-rebuild switch` on an enrolled host.

## Verify the daemon and enrollment

```bash
systemctl status cloudflare-warp.service          # warp-svc running
systemctl status cloudflare-warp-connect.service  # oneshot lifecycle (active/exited)
ls -l /var/lib/cloudflare-warp/mdm.xml            # 0600 root:root, present
warp-cli registration show                        # registration details
warp-cli registration organization                # expected: <team>
warp-cli status                                   # Connected
```

For an enrolled host, the `cloudflare-warp-connect` oneshot issues
verifies `warp-cli registration organization` against the managed team before
each connect request and polls `warp-cli status` on every attempt. A missing or
mismatched registration prevents `warp-cli connect`; an already connected
unmanaged tunnel is disconnected and logged at error priority. The loop makes up
to 30 attempts bounded by a 120-second deadline, with each `warp-cli` call capped
at five seconds. The retry window plus bounded registration/status checks remains
inside the unit's explicit `TimeoutStartSec=180`. The oneshot is best-effort: it
exits 0 and reaches `active (exited)` even when no request succeeds, logging
`connect never succeeded`, or when requests succeed but the final status remains
disconnected, logging `tunnel is not connected after <n> attempts`; use
`warp-cli registration organization` and `warp-cli status` rather than the unit
state to confirm the managed tunnel is up.
Without the sops secret, it logs UN-ENROLLED at warning priority and exits without connecting.

Confirm WARP is carrying traffic:

```bash
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E '^warp='   # warp=on
```

## Zero Trust dashboard checks

- The device appears under Team & Resources > Devices.
- For system76, Gateway DNS/HTTP logs show this device's queries (confirms Full
  mode + Gateway DNS).
- For tpnix, HTTP/policy telemetry is expected while private-host lookups remain
  served by the local NetworkManager dnsmasq configuration.

## Coexistence checks

- `tailscale status` is still reachable (confirms the `100.64.0.0/10`
  split-tunnel exclude).
- Internal / `.local` names resolve (confirms Local Domain Fallback).
- On tpnix, SignalX private-host names resolve through NetworkManager dnsmasq;
  this is expected because the host uses `tunnelonly`.

## Reapplying managed config

The `cloudflare-warp.service` carries a `restartTriggers` hash of the non-secret
mdm fields (`serviceMode`, `autoConnect`, `switchLocked`). Changing any of them
and rebuilding restarts `warp-svc`, which re-reads `mdm.xml`. The team name
(`organization`) and the service token live in the sops secret; rotating either
re-renders the `cloudflare-warp-mdm` template, whose `restartUnits` restarts
`warp-svc` on the next activation.

## Disable managed WARP

Set `programs.cloudflare-warp.extended.enable = false` and rebuild the host. When
the wrapper is disabled, its tmpfiles rule removes the wrapper-owned
`/var/lib/cloudflare-warp/mdm.xml` during the next NixOS activation, clearing the
runtime managed configuration and cached service token. This local cleanup does
not delete the device registration from the Zero Trust tenant. If full
de-enrollment is intended, run `sudo warp-cli registration delete` while the
daemon is still enabled and remove the device from Team & Resources > Devices
before disabling the module. Re-enabling the wrapper recreates `mdm.xml` from the
encrypted sops secret before `warp-svc` starts and can enroll the device again.

## Troubleshooting

- **Enrollment fails / device shows then drops.** The service token likely lacks
  device-enrollment permission. Add a Service Auth rule referencing the token
  (Deployment, step 3). Collect a diagnostics bundle: `sudo warp-diag`.

- **mdm.xml missing at boot (race).** `mdm.xml` is installed by an `ExecStartPre`
  that copies the sops-rendered template. Ordering is wired into the module:
  `cloudflare-warp.service` carries `after`/`requires` on the sops secret-install
  dependency (`config.flake.lib.security.sopsInstallSecretsDeps`), so on
  systemd-activation hosts the rendered template is present before `warp-svc`
  starts. Activation-script hosts decrypt secrets before any unit ordering. The
  connect oneshot waits for the daemon and makes up to 30 retry attempts within
  a 120-second deadline. Registration, connect, and status calls each have a
  five-second cap, and the oneshot has an explicit 180-second start timeout. The
  final `warp-cli status` and managed-registration checks are logged; if no request
  succeeds, managed registration is unavailable, or requests succeed while the
  status remains disconnected, the `<3>` prefix makes `connect never succeeded`,
  `managed enrollment is not ready`, or `tunnel is not connected after <n> attempts` visible to
  `journalctl -u cloudflare-warp-connect -p err`. The `<4>` UN-ENROLLED notice is visible to
  `journalctl -u cloudflare-warp-connect -p warning`. Inspect the daemon logs and rerun:

  `systemctl restart cloudflare-warp-connect.service`

  after enrollment is ready.

- **No connectivity with strict rp_filter.** The shared `hosts-common`
  `vpn-defaults` module sets `networking.firewall.checkReversePath = "loose"`
  for hosts that opt into the common baseline. If a host firewall module forces
  `strict`, the `CloudflareWARP` interface drops return traffic. The WARP module
  does not add a second owner for this setting.

- **DNS resolver conflict.** Full mode (`warp` / `1dot1`) makes WARP the DNS
  resolver. Do not also enable `services.dnscrypt-proxy` or NetworkManager's
  dnsmasq mode on `127.0.0.1:53`; the module warns when either local resolver
  is selected. Tpnix avoids the conflict by using `tunnelonly`.

- **General diagnostics.** `sudo warp-diag` writes a zip with logs and settings;
  `sudo warp-diag feedback` is the same bundle framed for a support ticket.
