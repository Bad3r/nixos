# Songbird troubleshooting

- [songbird-troubleshooting-windows.md](songbird-troubleshooting-windows.md)
- [songbird-troubleshooting-file-sharing.md](songbird-troubleshooting-file-sharing.md)
- [songbird-troubleshooting-local-ai.md](songbird-troubleshooting-local-ai.md)

## /data is empty after boot

The optional LUKS `data` volume stays closed when its initrd unlock prompt in `modules/hosts/songbird/hardware-config.nix` goes unanswered inside the bounded wait.

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

A run that outlasts the `docs` profile's `bisync.timeout` in `modules/lib/r2-runtime.nix` is stopped, and the next run starts its transfer over.

```sh
systemctl status r2-bisync-docs.service
journalctl -u r2-bisync-docs.service
```

Raise `bisync.timeout` on the `docs` profile in `modules/lib/r2-runtime.nix`, then switch and restart the unit, because a switch leaves the bisync units untouched.

## r2-bisync-docs warns `hash unexpectedly blank`

Objects uploaded through the R2 explorer carry no MD5, so the `docs` profile's checksum comparison falls back to size for them and warns on every run.

```sh
(set -a; . /run/secrets/r2/credentials.env; set +a
  rclone lsjson -R --fast-list --files-only --no-modtime --no-mimetype --hash \
    --exclude 'node_modules/**' --exclude '.venv/**' r2:nix-r2-cf-r2e-files-prod/docs) |
  jq -r '.[] | select(.Hashes.md5 == null) | .Path' > /tmp/r2-docs-no-md5.txt
```

Upload the listed files again from `/data/Docs` once `rclone check` finds them identical, since an rclone upload stores the MD5.

```sh
(set -a; . /run/secrets/r2/credentials.env; set +a
  rclone check --download --files-from /tmp/r2-docs-no-md5.txt /data/Docs r2:nix-r2-cf-r2e-files-prod/docs &&
  rclone copy --ignore-times --files-from /tmp/r2-docs-no-md5.txt /data/Docs r2:nix-r2-cf-r2e-files-prod/docs)
```
