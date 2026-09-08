# Songbird troubleshooting

Windows dual-boot and `/portal` entries are in [songbird-troubleshooting-windows.md](songbird-troubleshooting-windows.md).

## /data is empty after boot

The optional LUKS `data` volume stays closed when its initrd unlock prompt in `modules/songbird/hardware-config.nix` goes unanswered inside the bounded wait.

```sh
findmnt /data
```

Open the volume and mount it, then start the ownership unit and the writer gate by hand.

```sh
sudo cryptsetup open /dev/disk/by-id/ata-Samsung_SSD_860_PRO_2TB_S45DNF0K503930R-part1 data
sudo mount /data
sudo systemctl start data-ownership.service
sudo systemctl start r2-runtime-paths.service
```

## R2 mount, bisync, and restic units stay inactive

Every R2 writer unit carries its own `ConditionPathIsMountPoint` copy of the `/data` gate in `modules/lib/r2-runtime.nix`, beside the one on `r2-runtime-paths.service` it requires, so each is skipped independently once `/data` comes up unmounted.
A `requires` on a condition-skipped unit counts as satisfied and would not stop them.

```sh
systemctl status r2-runtime-paths.service r2-mount-docs.service
```

Mount `/data` first, then start the ownership unit, the gate, and the writer that is needed, because a condition-skipped unit never retries on its own.

```sh
sudo systemctl start data-ownership.service
sudo systemctl start r2-runtime-paths.service
sudo systemctl start r2-mount-docs.service
```

## Video turns choppy with NVRM API mismatch

A NixOS switch that changes the NVIDIA driver leaves the old kernel module loaded until reboot, so user space and the running module disagree on their API version.

```sh
journalctl -b | grep 'NVRM: API mismatch'
```

Reboot; reloading the kernel module is the only way to clear the mismatch.

## A build crashes with an internal compiler error

Heavy parallel compilation on this non-ECC host can corrupt an in-flight compile, so gcc or clang exits with SIGILL or SIGSEGV instead of a normal diagnostic.

```sh
nix build '/nix/store/<hash>-<name>.drv^*'
```

Retry the exact derivation named in the failure.
A repeat crash on the identical `.drv` rules out a transient fault and calls for the XMP fallback ladder in [songbird-hardware.md](songbird-hardware.md).

## Home Manager activation fails on a stale keyboxd lock

`keyboxd` can leave its dotlock file under `~/.gnupg/public-keys.d/` behind after an unclean stop, so the next Home Manager activation cannot open `pubring.db` and the switch aborts.

```sh
ls ~/.gnupg/public-keys.d/*.lock
```

Stop the daemon and clear the lock.

```sh
gpgconf --kill keyboxd
rip ~/.gnupg/public-keys.d/pubring.db.lock
```

## The r2-bisync-docs service never finishes

`r2-bisync-docs.service` lists `/data/Docs` with one HEAD request per object, and even the longer start timeout the docs profile sets in `modules/lib/r2-runtime.nix` can run out on a large enough tree.

```sh
systemctl status r2-bisync-docs.service
journalctl -u r2-bisync-docs.service
```

Raise `bisyncStartTimeout` on the `docs` profile in `modules/lib/r2-runtime.nix`, then switch and start the unit again.

## The Samba media share is missing

`modules/songbird/services.nix` detaches `samba.target` from `multi-user.target`, so smbd, nmbd, and wsdd stay down until the target is started by hand.
With the target running, the share itself is skipped with a warning when `secrets/songbird.yaml` is absent or `sopsRuntimeReady` in `modules/songbird/policy.nix` is false.
A present file with no `samba_media_path` key fails activation instead, with `the key 'samba_media_path' cannot be found` in the switch output.
Run both checks in the worktree that built the running generation, not `$HOME/nixos`: a bare `$HOME/nixos` path resolves as `git+file:`, and `self.submodules = true` fetches `secrets/` from its remote regardless of local init, so both checks can clear there even when the worktree's `secrets/` is empty.

```sh
systemctl is-active samba.target
ls secrets/songbird.yaml
nix eval "path:.#nixosConfigurations.songbird.config.warnings"
```

Start the units with `sudo systemctl start samba.target` when that target is inactive.
For an absent file, initialize the secrets submodule with `git submodule update --init --recursive`; `secrets/songbird.yaml` is tracked there, and `sops` against an empty checkout writes a stray file instead.
For a missing key, add it with `sops secrets/songbird.yaml`; for a false gate, set `sopsRuntimeReady = true` in `modules/songbird/policy.nix`.

## Evaluation warns about an unpinned interface name

`eth0` and `eth1` are kernel-assigned under `net.ifnames=0`, and if `firewallDnsInterfaces` in `modules/songbird/policy.nix` ever names one directly, `modules/hosts/common/firewall.nix` warns because nothing pins that name to a device.
Run the eval in the worktree with the edit; a bare `$HOME/nixos` path evaluates a different checkout and misses it.

```sh
nix eval "path:.#nixosConfigurations.songbird.config.warnings"
```

Replace that device's `altnamesOnly` entry in `modules/songbird/networking.nix` with an explicit `linkConfig` carrying `Name=` and `AlternativeNamesPolicy=` only, then name that pin in `firewallDnsInterfaces` in place of `eth0`.
The shared helper is where `NamePolicy=` comes from, and a file setting both keys fails the `modules/hosts/common/firewall.nix` assertion, as does a pin inside the kernel namespaces that [Pin an interface name](../networking/README.md#pin-an-interface-name) lists.
Never add a second `.link` file for the same device; udev reads only the first match.
