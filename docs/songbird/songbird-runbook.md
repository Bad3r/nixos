# Songbird runbook

Reinstall procedures are in [songbird-runbook-reinstall.md](songbird-runbook-reinstall.md), and Windows procedures in [songbird-runbook-windows.md](songbird-runbook-windows.md).

## Validate a host change

Precondition: the change sits in a linked worktree.

1. Run the format, check, and closure rungs of the [Validation ladder](../guides/host-onboarding.md#validation-ladder) with `songbird` as the host.

2. Commit the change, then switch on songbird:

   ```sh
   ./build.sh
   ```

3. Score the generation:

   ```sh
   nix run path:.#generation-manager -- score
   ```

Verification:

- `lsblk -o NAME,FSTYPE,UUID` shows `cryptroot`, `cryptswap`, and `data` mapped.
- `nvidia-smi` reports the GPU on the open kernel module.
- `ip -br link` shows `eth0`, `eth1`, and `wlan0`.
- `powerprofilesctl get` reports `performance`.
- `systemctl hibernate` round-trips, and `/portal` remounts on resume.
