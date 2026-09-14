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

- [x] **Step 2: Switch songbird to the branch.** The first switch left a symlink at `mdm.xml` and a
  Free registration behind; clear both first, since systemd resolves a symlink destination and
  warp-svc would still open the link.

```sh
sudo rm /var/lib/cloudflare-warp/mdm.xml
warp-cli --accept-tos registration delete
./build.sh
systemctl status cloudflare-warp
journalctl _PID="$(systemctl show -p MainPID --value cloudflare-warp)" | grep -c 'Too many levels of symbolic links'
```

Expected: switch exits 0, service active (running), the grep count is 0.
If not: read `journalctl -xeu cloudflare-warp` before retrying; do not rerun blind.

- [x] **Step 3: Check the sops-rendered mdm.xml.**

```sh
sudo cat /run/secrets/rendered/cloudflare-warp-mdm
sudo nsenter -t "$(systemctl show -p MainPID --value cloudflare-warp)" -m cat /var/lib/cloudflare-warp/mdm.xml
grep mdm.xml "/proc/$(systemctl show -p MainPID --value cloudflare-warp)/mountinfo"
```

Expected: both cat commands print the same dict: organization value, `service_mode` `warp`,
`auto_connect` 0, non-empty client id and secret for the `nixos-songbird` service token; the
mountinfo line shows `/var/lib/cloudflare-warp/mdm.xml` as a read-only bind of the rendered file
without sudo.
If not: same triage as Step 6.

- [x] **Step 4: Confirm registration, status, and DNS.**

```sh
warp-cli --accept-tos registration show
warp-cli --accept-tos status
cat /etc/resolv.conf
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E 'warp=|gateway='
```

Expected: registration bound to `nixos-songbird`, status reaches `Connected` with no manual
command (repeat after a reboot as in Step 8), `/etc/resolv.conf` names `127.0.2.2` and `127.0.2.3`,
and the trace prints `warp=on` and `gateway=on`. `resolvectl status` keeps showing eth0's servers and
no DNS on `CloudflareWARP`: warp-svc rejects systemd 261's version string and writes `resolv.conf`
directly instead of configuring resolved (see "resolvectl shows no DNS server on CloudflareWARP" in
`docs/cloudflare/warp/troubleshooting.md`).
If not: apply the registration and reboot checks for songbird; if `resolv.conf` never changes,
check that the `nixos-songbird` profile applied instead of the default profile.

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
sudo cat /run/secrets/rendered/cloudflare-warp-mdm
sudo nsenter -t "$(systemctl show -p MainPID --value cloudflare-warp)" -m cat /var/lib/cloudflare-warp/mdm.xml
```

Expected: both print the same dict: organization value, `service_mode` `tunnelonly`,
`auto_connect` 0, non-empty client id and secret for the `nixos-tpnix` service token.
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

- [ ] **Profiles: complete the exclude lists.** The `nixos-songbird` profile carries 17 entries and
  lacks `239.255.255.250/32` (SSDP), `fc00::/7`, and the five Apple ranges that Cloudflare serves
  by default (the consumer defaults songbird showed before enrollment); the runbook's profile step
  now lists all 24, and `nixos-tpnix` and the default profile take the same body.

```sh
cat > exclude.json <<'EOF'
[
  {"address": "10.0.0.0/8"},
  {"address": "100.64.0.0/11", "description": "CGNAT below the Cloudflare Mesh range"},
  {"address": "100.112.0.0/12", "description": "CGNAT above the Cloudflare Mesh range"},
  {"address": "169.254.0.0/16"},
  {"address": "172.16.0.0/12"},
  {"address": "192.0.0.0/24"},
  {"address": "192.168.0.0/16"},
  {"address": "224.0.0.0/24"},
  {"address": "239.255.255.250/32", "description": "SSDP"},
  {"address": "240.0.0.0/4"},
  {"address": "255.255.255.255/32"},
  {"address": "fe80::/10"},
  {"address": "fc00::/7"},
  {"address": "fd00::/8"},
  {"address": "ff01::/16"},
  {"address": "ff02::/16"},
  {"address": "ff03::/16"},
  {"address": "ff04::/16"},
  {"address": "ff05::/16"},
  {"address": "17.249.0.0/16", "description": "Apple services"},
  {"address": "17.252.0.0/16", "description": "Apple services"},
  {"address": "17.57.144.0/22", "description": "Apple services"},
  {"address": "17.188.128.0/18", "description": "Apple services"},
  {"address": "17.188.20.0/23", "description": "Apple services"}
]
EOF
curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/devices/policy/2d386bee-c816-47c2-8d45-a3b1353ab63c/exclude" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data @exclude.json
curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/devices/policy/<nixos-tpnix profile id>/exclude" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data @exclude.json
curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/devices/policy/exclude" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data @exclude.json
warp-cli --accept-tos settings | grep -c -E '239\.255\.255\.250/32|fc00::/7|17\.(249|252|57|188)\.'
```

Expected: each PUT answers `"success": true`; after the profile refresh (up to ten minutes, or a
restart of `cloudflare-warp.service`), the grep count on songbird is 7.
If not: `GET /accounts/$ACCOUNT/devices/policies` shows which profile still carries 17 entries.

- [ ] **Step 10: SSH both directions over Mesh.** Only once both hosts show Connected.

```sh
ssh songbird.warp   # from tpnix
ssh tpnix.warp      # from songbird
```

Optional: `nc -vz <meshIp> 22` and, since the ICMP proxy is on, `ping <meshIp>`.
Early check with the iPhone, enrolled on the default profile: from an SSH client app on the phone,
`ssh vx@100.96.0.9` proves songbird's inbound Mesh path (firewall rule and sshd; the phone has no
host-key pin), and `ping <phone device address>` from songbird proves the ICMP proxy. The phone's
device address is in the same Devices list. Passed for songbird inbound: sshd logged
`Accepted keyboard-interactive/pam for vx from 100.96.0.8`, and `ping 100.96.0.8` from songbird
answered three of three, so only tpnix's half of Step 10 is open.
Pass: both directions succeed; record each host's `meshIp` in `modules/<host>/policy.nix` as a
follow-up commit (this is also what renders the `.warp` ssh aliases and known_hosts pins on the
next switch). songbird's address is recorded already, so tpnix renders `songbird.warp` and its
host-key pin on its first switch; tpnix's address lands after Step 7, then songbird switches once
more for `tpnix.warp`.
Fail: with tpnix still in `tunnelonly`, fall back to switching tpnix's Cloudflare device
profile mode and its NixOS `serviceMode` to `warp`, then retest. Read "Private hostnames stop
resolving on tpnix" in `docs/cloudflare/warp/troubleshooting.md` first.

- [ ] **Step 11: Verify the device registrations in the dashboard.** Zero Trust dashboard,
  Team & Resources > Devices > Devices list.
  Expected: exactly three registrations: two with identity `non_identity@repo.cloudflareaccess.com`,
  one matching device profile `nixos-tpnix` (precedence 100) and one matching `nixos-songbird`
  (precedence 200), plus the iPhone under the user's own identity on the default profile; all
  Connected.
  If not: an extra or missing `non_identity` registration means a host registered under the wrong
  token; delete the stray registration and recheck Step 4 or Step 7 for that host.

## Code follow-ups noted by the final branch review (none block the merge)

- `serviceMode` is forced only on the enrolled branch, so CI (which has no secrets submodule) cannot catch an
  enabled host that forgets to set it; the error surfaces at switch time instead.
- On the enrolled path the WARP package lands in `environment.systemPackages` twice (app module plus upstream
  service module); identical store path, deduplicated by buildEnv, so cosmetic only.
- `docs/cloudflare/warp/README.md` states the IPv6-disabled kernel parameter as settled where the design lists it as
  a risk until the first switch proves WARP connects under it.
