# Songbird runbook

Reinstall procedures are in [songbird-runbook-reinstall.md](songbird-runbook-reinstall.md), and Windows procedures in [songbird-runbook-windows.md](songbird-runbook-windows.md).

## Validate a host change

Precondition: the change sits in a linked worktree whose `secrets/` submodule is initialized (`git submodule update --init --recursive`).
A linked worktree always takes the `path:` reference, which copies the tree instead of fetching it, so `self.submodules = true` never applies and an uninitialized `secrets/` builds a generation with every `sops.secrets` declaration dropped.

1. Run the format, check, and closure rungs of the [Validation ladder](../guides/host-onboarding.md#validation-ladder) with `songbird` as the host.

2. Commit the change, then switch on songbird:

   ```sh
   ./build.sh
   ```

3. Score the generation:

   ```sh
   git status --porcelain --ignored=matching
   git submodule foreach --recursive 'git status --porcelain --ignored=matching'
   bash -c 'source scripts/lib/secrets-guard.sh && secrets_guard_enforce "$PWD" "path:$PWD"' &&
     nix run path:.#generation-manager -- score
   ```

Verification:

- `lsblk -o NAME,FSTYPE,UUID` shows `cryptroot`, `cryptswap`, and `data` mapped.
- `cat /proc/driver/nvidia/version` names the open kernel module, and `nvidia-smi` lists the GPU.
- `ip -br link` shows `eth0`, `eth1`, and `wlan0`.
- `powerprofilesctl get` reports `performance`.
- `systemctl hibernate` round-trips, and `/portal` remounts on resume.
