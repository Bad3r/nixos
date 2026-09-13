# WARP Operations

Runtime verification, coexistence checks, and troubleshooting after
`nixos-rebuild switch` on an enrolled host.

## Verify the daemon and enrollment

```bash
systemctl status cloudflare-warp.service          # warp-svc running
systemctl status cloudflare-warp-connect.service  # oneshot lifecycle (active/exited)
ls -l /var/lib/cloudflare-warp/mdm.xml            # 0600 root:root, present
warp-cli --accept-tos registration show           # registration details
warp-cli --accept-tos registration organization   # expected: <team>
warp-cli --accept-tos status                      # Connected
```

For an enrolled host, the `cloudflare-warp-connect` oneshot verifies
`warp-cli registration organization` against the managed team before its first
connect request and polls `warp-cli status` on every attempt. The first request
requires a confirmed match. Within the same run, a later unanswered registration
response may retry a connection from that confirmation only while no successful
empty response is held and no later successful check has recorded a mismatch. A
successful empty response cannot verify a connected tunnel or authorize another
connect request. A confirmed mismatch, which is what a consumer or still-unregistered
device reports, disconnects an already connected tunnel and logs at error priority.
A registration check that does not answer within its five-second cap leaves an
existing tunnel up, because an unanswered check is not evidence of an unmanaged
tunnel. With neither a pending empty-answer hold nor a retained conclusive mismatch,
three such observations on a live tunnel end the loop, since nothing is left to
request.
Neither an unanswered check nor the first three successful answers naming no
organization is treated as a mismatch while the daemon may still be settling: an
enrolled daemon returns an empty answer transiently before it has loaded its
registration. A fresh managed confirmation resets that readiness window, so the
first three successful empty answers after startup or that confirmation are held.
A failed check cannot resolve that hold, so it stays in place until a later successful
response confirms or mismatches. This prevents an interleaved timeout from spending
the unverified budget before a fourth empty answer can disconnect a consumer tunnel.
Both are missing information rather than evidence of a re-registration. An answer
naming a different team is a mismatch immediately and still disconnects. A retained
mismatch also prevents a later empty answer from reopening the hold, so a fresh
successful empty or foreign answer re-enters cleanup.
A later unanswered check cannot refute a mismatch already observed in this run, so
its non-identifying classification remains available to the terminal diagnostic
until a managed confirmation replaces it. That retained classification also prevents
an earlier confirmation from treating a later `Connected` status as verified or a
later empty answer from reopening the readiness hold. It never turns a failed query
into disconnect evidence. Instead, it preserves the remaining attempt and deadline
budget for a fresh registration result to retry cleanup. An empty,
unreadable, or whitespace-only organization secret cannot change while the unit
runs, so the oneshot reports the current status once and exits instead of
retrying a decision that can never open.
The loop makes up to 30 attempts bounded by a 120-second deadline, with each
`warp-cli` call capped at five seconds and killed one second later if it ignores
the term signal, so no call can outlast its cap. The retry window plus bounded registration/status checks remains
inside the unit's explicit `TimeoutStartSec=180`. The oneshot is best-effort: it
exits 0 and reaches `active (exited)` in every outcome, so read the final log
line rather than the unit state:

| Final line                                                | Meaning                                                                             |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| (none)                                                    | Managed tunnel verified and up                                                      |
| `tunnel is up but its registration went unverified`       | Tunnel left connected; managed registration remained unverified                     |
| `daemon reports no Zero Trust registration`               | Last conclusive registration showed no Teams registration                           |
| `daemon is registered outside the managed organization`   | Last conclusive registration belonged to another tenant                             |
| `tunnel is not connected after <n> attempts`              | Connect was accepted, but the tunnel never read `Connected` in the window           |
| `connect never succeeded (daemon unreachable ...)`        | No connect ever succeeded: never requested, or refused on every attempt             |
| `managed organization secret unavailable; not connecting` | Secret missing, unreadable, or whitespace-only; the run exits before the retry loop |

The rows are mutually exclusive. They normally reflect the state the run ended
on, including an unverified line only when the last status query still read
`Connected`. A conclusive mismatch remains the exception: a later unanswered
check cannot prove the earlier mismatch resolved, so that diagnostic survives
until a successful managed confirmation clears it. The retained classification is
not disconnect evidence after the live state became unknown. It prevents an earlier
confirmation from accepting a later connected tunnel as managed and a later empty
answer from reopening the readiness hold until a successful managed confirmation
clears the mismatch. It also leaves `unverified` unchanged, so the bounded loop can
obtain a fresh result and retry cleanup without letting the unanswered probe itself
select disconnect.

Use `warp-cli --accept-tos registration organization` and
`warp-cli --accept-tos status` to confirm the managed tunnel is up. Without the
sops secret the daemon and this unit do not exist; only `warp-cli` is installed.

Confirm WARP is carrying traffic:

```bash
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E '^warp='   # warp=on
```

## Zero Trust dashboard checks

- The device appears under Team & Resources > Devices.
- For songbird, Gateway DNS/HTTP logs show this device's queries (confirms Full
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
de-enrollment is intended, run `sudo warp-cli --accept-tos registration delete` while the
daemon is still enabled and remove the device from Team & Resources > Devices
before disabling the module. Re-enabling the wrapper recreates `mdm.xml` from the
encrypted sops secret before `warp-svc` starts and can enroll the device again.

## Troubleshooting

Known failures, their diagnostics, and fixes live in
[troubleshooting.md](troubleshooting.md).
