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

Every R2 writer unit requires `r2-runtime-paths.service`, whose `ConditionPathIsMountPoint=/data` gate in `modules/lib/r2-runtime.nix` skips it once `/data` comes up unmounted.

```sh
systemctl status r2-runtime-paths.service
```

Mount `/data` first, then start the gate and the writer that is needed, because a condition-skipped unit never retries on its own.

```sh
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
nix build /nix/store/<hash>-<name>.drv^*
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

The upstream R2 flake module exposes no compare or exclude setting, so the timeout is the only lever available.
Track the fix at https://github.com/Bad3r/nix-R2-CloudFlare-Flake/issues/150 and the consumer side at https://github.com/Bad3r/nixos/issues/477.

## The Samba media share is missing

`modules/songbird/services.nix` skips the share and warns when `secrets/songbird.yaml` is absent or `sopsRuntimeReady` in `modules/songbird/policy.nix` is false.
A present file with no `samba_media_path` key fails activation instead, with `the key 'samba_media_path' cannot be found` in the switch output.

```sh
nix eval "path:.#nixosConfigurations.songbird.config.warnings"
```

Add the key with `sops secrets/songbird.yaml`, or set `sopsRuntimeReady = true` in `modules/songbird/policy.nix`.

## Evaluation warns about an unpinned interface name

`eth0` and `eth1` are kernel-assigned under `net.ifnames=0`, and if `firewallDnsInterfaces` in `modules/songbird/policy.nix` ever names one directly, `modules/hosts/common/firewall.nix` warns because nothing pins that name to a device.

```sh
nix eval "path:.#nixosConfigurations.songbird.config.warnings"
```

Add `Name=` to the device's existing entry in `modules/songbird/networking.nix` and drop its `NamePolicy=`.
Never add a second `.link` file for the same device; udev reads only the first match.
