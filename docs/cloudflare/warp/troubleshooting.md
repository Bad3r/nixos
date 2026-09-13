# WARP Troubleshooting

Known failures after `nixos-rebuild switch` on an enrolled host, each with its
cause, diagnostic, and fix. Runtime checks live in [operations.md](operations.md).

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
  `journalctl -u cloudflare-warp-connect -p err`. Each attempt with neither a
  fresh confirmation nor an unanswered probe after a same-run confirmation with
  no pending empty-answer hold or retained mismatch instead logs
  `registration check failed (exit <n>)`,
  `managed Zero Trust registration unavailable`, or `managed enrollment is not ready; not connecting`
  at `<4>`, as do `status command failed` and `connect request failed`, which carry the daemon's
  own reason for refusing a call: the daemon IPC socket and the managed registration settle at
  different times, so a healthy boot emits several of these before the run ends confirmed and
  connected. An answer naming no organization logs
  `registration check returned no organization; not treating it as a mismatch yet` at `<4>` rather
  than counting as a mismatch during the first three successful empty answers
  after startup or a fresh confirmation. A fresh confirmation resets that
  readiness window. A retained mismatch prevents a later empty answer from
  reopening the hold, so a connected tunnel returns to mismatch handling and
  cleanup is attempted. A failed registration check does not clear either
  preserved state: an unanswered probe can retry a refused connection after a
  prior confirmation only when no empty-response hold or mismatch is retained,
  while a prior mismatch keeps its attempt and deadline budget for a fresh response
  to retry cleanup. A fourth successful empty response reaches mismatch and can
  disconnect a consumer tunnel. A tunnel found up during the
  hold logs `tunnel is up while the registration is still settling` at `<4>`,
  recording that teardown is deferred rather than that registration was verified.
  If the daemon remains unavailable after an empty answer, the existing 30-attempt
  or 120-second bound ends the best-effort unit instead.
  `-p err` therefore stays quiet through a normal warm-up, and `-p warning` shows the attempts.
  If an existing tunnel is confirmed to carry a
  registration other than the managed one, the unit logs `connected without managed Zero Trust registration; disconnecting`; a failed cleanup logs `failed to disconnect unmanaged tunnel`. When the
  registration check itself does not answer with no active empty-answer hold or
  retained mismatch, the tunnel is left up and the unit logs `connected while the managed registration could not be verified; leaving the tunnel up` at warning
  priority. After a conclusive mismatch and an unsuccessful cleanup, a later failed
  registration check instead logs `tunnel is up after a conclusive registration mismatch; waiting for a fresh registration check before retrying cleanup` and keeps
  the existing attempt and deadline budget for a fresh result. It does not disconnect
  on the failed check. An empty,
  unreadable, or whitespace-only organization secret logs `managed organization secret unavailable; cannot verify registration`, queries the daemon once so the tunnel's state is on record, then logs `managed organization secret unavailable; not connecting` before the unit exits without entering the retry loop. Both of those are `<3>` lines, visible to
  `journalctl -u cloudflare-warp-connect -p err`. A registration query that does
  not answer logs `registration check failed (exit <n>)`; exit 124 is the five-second
  `timeout` firing on a busy `warp-svc` and 137 is the `-k 1s` SIGKILL for a call that
  ignored the term signal, both pointing at the daemon rather than the CLI. Any other
  code is warp-cli's own, whose stderr is left unredirected and lands in the journal
  beside it at info priority.
  Inspect the daemon logs and rerun:

  `systemctl restart cloudflare-warp-connect.service`

  after enrollment is ready. The oneshot runs once per boot and does not retry
  after its 120-second window closes: it exits 0, `RemainAfterExit` leaves it
  `active (exited)`, and `autoConnect = 0` means `warp-svc` never self-connects.
  A first enrollment slower than that window, behind a captive portal or on a
  slow first token exchange, therefore ends on `connect never succeeded` and the
  host stays untunneled until this restart or the next boot. There is
  deliberately no retry timer: one would also reconnect a tunnel the user had
  disconnected on purpose, which is what `autoConnect = 0` exists to prevent.

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
