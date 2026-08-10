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

For an enrolled host, the `cloudflare-warp-connect` oneshot verifies
`warp-cli registration organization` against the managed team before each
connect request and polls `warp-cli status` on every attempt. Only a confirmed
match permits `warp-cli connect`. A confirmed mismatch, which is what a consumer
or still-unregistered device reports, disconnects an already connected tunnel and
logs at error priority. A registration check that does not answer within its
five-second cap leaves an existing tunnel up, because an unanswered check is not
evidence of an unmanaged tunnel; after three such observations on a live tunnel
the loop stops, since nothing is left to request. Neither an unanswered check nor an
answer naming no organization counts against a run that already read the managed
organization: that value cannot change mid-run, so both are missing information
rather than evidence of a re-registration, and the read is what allowed connect
in the first place. An answer naming a different team is still a mismatch and
still disconnects. An empty or unreadable
organization secret cannot change while the unit runs, so the oneshot reports the
current status once and exits instead of retrying a decision that can never open.
The loop makes up to 30 attempts bounded by a 120-second deadline, with each
`warp-cli` call capped at five seconds and killed one second later if it ignores
the term signal, so no call can outlast its cap. The retry window plus bounded registration/status checks remains
inside the unit's explicit `TimeoutStartSec=180`. The oneshot is best-effort: it
exits 0 and reaches `active (exited)` in every outcome, so read the final log
line rather than the unit state:

| Final line                                                | Meaning                                                                             |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| (none)                                                    | Managed tunnel verified and up                                                      |
| `tunnel is up but its registration went unverified`       | Tunnel left connected; the registration check never answered                        |
| `daemon reports no Zero Trust registration`               | No Teams registration; enrollment incomplete or rejected                            |
| `daemon is registered outside the managed organization`   | Live registration belongs to another tenant                                         |
| `tunnel is not connected after <n> attempts`              | Connect was accepted, but the tunnel never read `Connected` in the window           |
| `connect never succeeded (daemon unreachable ...)`        | No connect ever succeeded: never requested, or refused on every attempt             |
| `managed organization secret unavailable; not connecting` | Secret missing, unreadable, or whitespace-only; the run exits before the retry loop |

The rows are mutually exclusive and reflect the state the run ended on, not
anything observed along the way: a confirmed mismatch is reported ahead of the
others, and the unverified line requires the last status query to have still
read `Connected`. An earlier attempt that could not verify a tunnel therefore
does not colour the final line once the run ends somewhere else.

Use `warp-cli registration organization` and `warp-cli status` to confirm the
managed tunnel is up. Without the sops secret the daemon and this unit do not
exist; only `warp-cli` is installed.

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

The `cloudflare-warp-mdm` template's `restartUnits` is the single restart owner
for `warp-svc`. sops compares the rendered template between generations, so both
a changed mdm field (`serviceMode`, `autoConnect`, `switchLocked`) and a rotated
team name or service token restart the daemon on the next activation, which
re-reads `mdm.xml`. The unit carries no `restartTriggers` hash of its own: a
second owner restarts `warp-svc` twice for one activation on hosts running
`sops.useSystemdActivation`, dropping the tunnel twice.

Each restart of `warp-svc` also re-runs `cloudflare-warp-connect`, so the tunnel
comes back without a manual step. An explicit restart, which is what sops issues
when the rendered `mdm.xml` changes, reaches the oneshot through `BindsTo=`; an
unexpected `warp-svc` exit reaches it through `Upholds=`, because `BindsTo=`
stops the oneshot before the restart can propagate to it.

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

- **`warp-svc` refuses to start after a credential rotation.** The first
  `ExecStartPre` runs `xmllint --noout` over the rendered template, and
  `cloudflare-warp.service` fails with
  `cloudflare-warp: rendered mdm.xml is not well-formed; a credential likely contains an XML metacharacter`.
  One of `organization`, `auth_client_id`, or `auth_client_secret` contains a
  bare `&`, `<`, or an unterminated entity. xmllint's own diagnostic is
  discarded rather than logged, because it reports a parse error by echoing the
  offending source line, which is the credential itself. Re-issue the service
  token, or `sops secrets/cloudflare-warp.yaml` and check the three values, then
  rebuild. Compare against the decrypted payload rather than the journal.

- **mdm.xml missing at boot (race).** `mdm.xml` is installed by an `ExecStartPre`
  that copies the sops-rendered template. Ordering is wired into the module:
  `cloudflare-warp.service` carries `after`/`requires` on the sops secret-install
  dependency (`config.flake.lib.security.sopsInstallSecretsDeps`), so on
  systemd-activation hosts the rendered template is present before `warp-svc`
  starts. Activation-script hosts decrypt secrets before any unit ordering. The
  connect oneshot waits for the daemon and makes up to 30 retry attempts within
  a 120-second deadline. Registration, connect, and status calls each have a
  five-second cap (`timeout -k 1s 5s`, so a call that ignores the term signal is
  killed rather than left running), and the oneshot has an explicit 180-second start timeout. The
  final `warp-cli status` and managed-registration checks are logged; if no request
  succeeds, managed registration is unavailable, or requests succeed while the
  status remains disconnected, the `<3>` prefix makes `connect never succeeded`
  or `tunnel is not connected after <n> attempts` visible to
  `journalctl -u cloudflare-warp-connect -p err`. Each attempt that has not yet confirmed the
  managed registration instead logs `registration check failed (exit <n>)`,
  `managed Zero Trust registration unavailable`, or `managed enrollment is not ready; not connecting`
  at `<4>`, as do `status command failed` and `connect request failed`, which carry the daemon's
  own reason for refusing a call: the daemon IPC socket and the managed registration settle at different times, so a
  healthy boot emits several of these before the run ends confirmed and connected. `-p err`
  therefore stays quiet through a normal warm-up, and `-p warning` shows the attempts.
  If an existing tunnel is confirmed to carry a
  registration other than the managed one, the unit logs `connected without managed Zero Trust registration; disconnecting`; a failed cleanup logs `failed to disconnect unmanaged tunnel`. When the
  registration check itself does not answer, the tunnel is left up and the unit
  logs `connected while the managed registration could not be verified; leaving the tunnel up` at warning priority. An empty
  or unreadable organization secret logs `managed organization secret unavailable; cannot verify registration`, queries the daemon once so the tunnel's state is on record, then logs `managed organization secret unavailable; not connecting` before the unit exits without entering the retry loop. Both of those are `<3>` lines, visible to
  `journalctl -u cloudflare-warp-connect -p err`. A registration query that does
  not answer logs `registration check failed (exit <n>)`; exit 124 is the five-second
  `timeout` firing on a busy `warp-svc` and 137 is the `-k 1s` SIGKILL for a call that
  ignored the term signal, both pointing at the daemon rather than the CLI. Any other
  code is warp-cli's own, whose stderr is left unredirected and lands in the journal
  beside it at info priority.
  Inspect the daemon logs and rerun:

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
