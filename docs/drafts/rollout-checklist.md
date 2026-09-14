# Cloudflare WARP rollout checklist

Private working file, not for the PR body. Ids and hostnames are fine here; never write a
client secret into this file. Rollback commands for every object live in `cloudflare-changes.md`.
Run the songbird steps first, then tpnix, then the cross-host gate.

## songbird

- [x] **Step 1: ProtonVPN autoconnect off before enrolling.** WARP and ProtonVPN together is
  unsupported.

```sh
nmcli con mod "<ProtonVPN connection>" connection.autoconnect no
nmcli -t -f connection.autoconnect con show "<ProtonVPN connection>"
```

Expected: `connection.autoconnect:no`.
If not: rerun with the exact connection name from `nmcli con show`; do not switch songbird
while Proton still autoconnects.

- [x] **Step 2: Switch songbird to the branch.**

```sh
./build.sh
systemctl status cloudflare-warp
```

Expected: switch exits 0, service active (running).
If not: read `journalctl -xeu cloudflare-warp` before retrying; do not rerun blind.

- [ ] **Step 3: Check the sops-rendered mdm.xml.**

```sh
sudo cat /var/lib/cloudflare-warp/mdm.xml
```

Expected: organization value, `service_mode` `warp`, `auto_connect` 0, non-empty client id and
secret for the `nixos-songbird` service token.
If not: same triage as Step 6.

- [ ] **Step 4: Confirm registration, status, and DNS.**

```sh
warp-cli --accept-tos registration show
warp-cli --accept-tos status
resolvectl status
```

Expected: registration bound to `nixos-songbird`, status reaches `Connected` with no manual
command (repeat after a reboot as in Step 8), resolver shows WARP with Gateway DNS in effect.
If not: apply the registration and reboot checks for songbird; if the resolver never shows WARP,
check that the `nixos-songbird` profile applied instead of the default profile.

2026-09-14 reverted to unchecked: the switch's own journal shows `warp_settings::manager: Unable to read local policy file e=Too many levels of symbolic links (os error 40)` at
warp-svc startup, then `warp_primitives::access: Service token credentials not configured: missing organization`. `warp-cli registration show` reports `Account type: Free` with no
organization, unchanged across a recheck 47 minutes and 517 network-change events later. This
is the "Registration missing after the switch" case in `docs/cloudflare/warp/troubleshooting.md`,
but its documented fix does not clear it: a manual `sudo systemctl restart cloudflare-warp.service`
on songbird reproduced the identical `Unable to read local policy file ... os error 40` on the new
PID, immediately. This is not a one-time startup race; it is structural, most likely warp-svc
opening `mdm.xml` with O_NOFOLLOW against a path that `sops.templates` renders as a symlink into
`/run/secrets` (an O_NOFOLLOW open against a symlinked last path component fails with ELOOP
regardless of chain depth or timing). Blocker: do not check Steps 3 and 4, and do not proceed to
tpnix or the cross-host gate, until `modules/apps/cloudflare-warp.nix` delivers `mdm.xml` as a
plain file at the path warp-svc opens rather than a symlink into `/run/secrets`, and a fresh
switch shows a non-Free registration bound to `nixos-songbird`.

## tpnix

- [ ] **Step 5: Switch tpnix to the merged branch.**

```sh
./build.sh
systemctl status cloudflare-warp
```

Expected: switch exits 0 and the service is active (running).
If not: read `journalctl -xeu cloudflare-warp` before retrying; do not rerun blind.

- [ ] **Step 6: Check the sops-rendered mdm.xml.**

```sh
sudo cat /var/lib/cloudflare-warp/mdm.xml
```

Expected: organization value, `service_mode` `tunnelonly`, `auto_connect` 0, non-empty client
id and secret for the `nixos-tpnix` service token.
If not: the sops secret or template did not render; sops-nix runs in the activation script here (no
unit), so reread the switch output for `sops-install-secrets` errors and check
`ls -la /run/secrets/rendered/cloudflare-warp-mdm` before continuing.

- [ ] **Step 7: Confirm registration and status.**

```sh
warp-cli --accept-tos registration show
warp-cli --accept-tos status
warp-cli --accept-tos settings | grep -i mode
```

Expected: registration bound to the `nixos-tpnix` token (non_identity, no browser flow),
status reaches `Connected` with no manual connect, the mode line names a tunnel-only mode
(the API spells it `warp_tunnel_only`; the CLI label may differ in case).
If not: for registration, `warp-cli --accept-tos registration delete` then restart
`cloudflare-warp.service`; for mode, recheck the device profile matched on
`identity.service_token_uuid` before touching the profile itself.

- [ ] **Step 8: Reboot and repeat the auto-connect check.** Reboot also activates
  `ipv6.disable=1`, the first real test of that against WARP.

```sh
warp-cli --accept-tos status
```

Expected: `Connected` again with no manual command.
If not: apply the design's fallback (section 11), a small oneshot systemd unit that runs
`warp-cli --accept-tos connect` after `cloudflare-warp.service` (not yet in the branch); do not
assume this is the IPv6 blocker (Step 9) until the fallback has been tried.

- [ ] **Step 9: IPv6-disabled kernel parameter check.**

```sh
warp-diag
journalctl -u cloudflare-warp -b
```

Expected: WARP reaches Connected and assigns its device address even with `ipv6.disable=1`.
If not: this is a blocker, not something to work around; report it with the `warp-diag`
archive and the journal excerpt, per the design's risk list (section 11).

## Cross-host go/no-go gate

- [ ] **Step 10: SSH both directions over Mesh.** Only once both hosts show Connected.

```sh
ssh songbird.warp   # from tpnix
ssh tpnix.warp      # from songbird
```

Optional: `nc -vz <meshIp> 22` and, since the ICMP proxy is on, `ping <meshIp>`.
Pass: both directions succeed; record each host's `meshIp` in `modules/<host>/policy.nix` as a
follow-up commit (this is also what renders the `.warp` ssh aliases and known_hosts pins on the
next switch).
Fail: with tpnix still in `tunnelonly`, fall back to switching tpnix's Cloudflare device
profile mode and its NixOS `serviceMode` to `warp`, then retest. Read "Private hostnames stop
resolving on tpnix" in `docs/cloudflare/warp/troubleshooting.md` first.

- [ ] **Step 11: Verify both device registrations in the dashboard.** Zero Trust dashboard,
  Team & Resources > Devices > Devices list.
  Expected: exactly two registrations, both identity `non_identity@repo.cloudflareaccess.com`,
  one matching device profile `nixos-tpnix` (precedence 100) and one matching `nixos-songbird`
  (precedence 200), both Connected.
  If not: an extra or missing registration means a host registered under the wrong token; delete
  the stray registration and recheck Step 4 or Step 7 for that host.

## Code follow-ups noted by the final branch review (none block the merge)

- `serviceMode` is forced only on the enrolled branch, so CI (which has no secrets submodule) cannot catch an
  enabled host that forgets to set it; the error surfaces at switch time instead.
- On the enrolled path the WARP package lands in `environment.systemPackages` twice (app module plus upstream
  service module); identical store path, deduplicated by buildEnv, so cosmetic only.
- `docs/cloudflare/warp/README.md` states the IPv6-disabled kernel parameter as settled where the design lists it as
  a risk until the first switch proves WARP connects under it.
