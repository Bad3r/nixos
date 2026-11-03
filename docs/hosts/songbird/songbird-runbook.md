# Songbird runbook

- [songbird-runbook-reinstall.md](songbird-runbook-reinstall.md)
- [songbird-runbook-windows.md](songbird-runbook-windows.md)
- [songbird-runbook-portal.md](songbird-runbook-portal.md)
- [songbird-runbook-vms.md](songbird-runbook-vms.md)
- [songbird-runbook-win11.md](songbird-runbook-win11.md)
- [songbird-runbook-win11-use.md](songbird-runbook-win11-use.md)
- [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md)
- [songbird-runbook-paperless.md](songbird-runbook-paperless.md)

## Validate a host change

Precondition: the change sits in a linked worktree whose `secrets/` submodule is initialized (`git submodule update --init --recursive`).
A linked worktree always takes the `path:` reference, which copies the tree instead of fetching it, so `self.submodules = true` never applies.
An uninitialized `secrets/` then builds a generation with every `sops.secrets` declaration dropped.

1. Run the format, check, and closure rungs of the [Validation ladder](../../guides/host-onboarding.md#validation-ladder) with `songbird` as the host.

2. Commit the change, then switch on songbird:

   ```sh
   ./build.sh
   ```

Verification:

- `lsblk -o NAME,FSTYPE,UUID` shows `cryptroot`, `cryptswap`, and `data` mapped.
- `cat /proc/driver/nvidia/version` names the open kernel module, and `nvidia-smi` lists the GPU.
- `ip -br link` shows `eth0`, `eth1`, and `wlan0`.
- `powerprofilesctl get` reports `performance`.
- `systemctl hibernate` round-trips, and `/portal` remounts on resume.

## Capture the monitor EDID

Precondition: the monitor is awake, `xrandr` lists `DP-4 connected`, and X runs without a stored EDID.
X reports the stored EDID in place of the panel's own, so for a new monitor first remove `secrets/songbird-monitor.edid` with a commit in `secrets`, commit the submodule bump, switch, and restart X.
A build reads `secrets/` at its committed revision, so an uncommitted deletion leaves the stored EDID in place.
`grep CustomEDID /var/log/X.0.log` prints nothing once X runs without it.

1. From the repository root, capture the panel's EDID into a temporary file and decode it:

   ```sh
   edid=$(mktemp)
   DISPLAY=:0 xrandr --props |
     awk '/^DP-4 connected/ {o = 1; next} /^[^ \t]/ {o = 0}
          o && /EDID:/ {e = 1; next} e && /^\t\t[0-9a-f]+$/ {gsub(/\t/, ""); printf "%s", $0; next} {e = 0}' |
     xxd -r -p > "$edid"
   nix shell nixpkgs#edid-decode -c edid-decode "$edid" | grep 'Display Product Name'
   ```

   Stop when the last command prints nothing, since the capture then holds no EDID.

2. Encrypt it into the secrets repository and push that repository's `main`:

   ```sh
   sops encrypt --input-type binary --output-type binary \
     --filename-override secrets/songbird-monitor.edid --output secrets/songbird-monitor.edid "$edid"
   rm "$edid"
   git -C secrets add songbird-monitor.edid
   git -C secrets commit -m "chore: update songbird-monitor.edid"
   git -C secrets push origin HEAD:main
   ```

3. Commit the submodule bump, switch, and restart X, which ends the desktop session:

   ```sh
   sudo systemctl restart display-manager
   ```

Verification: with the monitor off, `DISPLAY=:0 xrandr --listactivemonitors` still lists `DP-4`.
