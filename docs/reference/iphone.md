# iPhone support

Apple ships no iOS tooling for Linux; pairing, mounts, backups, and tethering use the community stack.
USB integration uses these modules:

- [usbmuxd](../../modules/apps/usbmuxd.nix) supplies the pairing daemon through `services.usbmuxd.extended`, required by every USB path including tethering trust.
- [libimobiledevice](../../modules/apps/libimobiledevice.nix) supplies `idevicepair`, `ideviceinfo`, `idevicebackup2`, `afcclient`, and `idevicesyslog`.
- [ifuse](../../modules/apps/ifuse.nix) mounts the media filesystem and per-app Documents folders through FUSE.
- [gphoto2](../../modules/apps/gphoto2.nix) supplies scriptable PTP camera-roll import.
- [Common services](../../modules/hosts/common/services.nix) enables the GVfs AFC and gphoto2 backends.
- [LocalSend](../../modules/apps/localsend.nix) uses port 53317 for network transfers.

[Common app defaults](../../modules/hosts/common/apps-enable.nix) enables the tools; per-host app overrides can opt out.
The libimobiledevice and ifuse assertions require usbmuxd to stay enabled.

## Pairing and trust

Connect with a data-capable cable, unlock the phone, then:

```sh
idevicepair pair      # accept the trust dialog on the phone, run again
idevicepair validate
ideviceinfo -k ProductVersion
```

Major iOS upgrades can invalidate the stored pair record.
When lockdownd starts refusing connections, reset it:

```sh
idevicepair unpair && idevicepair pair
```

## File transfer

[File transfer](iphone-file-transfer.md) covers the default file manager, bulk copies, app documents, PTP imports, network transfers, and large files.

## Backup

```sh
mkdir -p ~/backups/iphone
idevicebackup2 encryption on -i
idevicebackup2 backup --full ~/backups/iphone
```

Prefer encrypted backups: they include health and keychain data that unencrypted backups omit.
Password-handling subcommands need `-i` to prompt, or `BACKUP_PASSWORD_NEW` and `BACKUP_PASSWORD` in the environment.
Without either, the tool refuses to read a password and exits before contacting the device.
Create the top-level backup directory first; the tool creates only the per-device folder inside it.

The `list` subcommand is broken upstream.
Full backups of a large phone take hours at AFC-class throughput.
`backup --full` updates the existing set under `<dir>/<udid>/` in place rather than writing a new dated copy.

`restore --system --settings` overwrites the phone's system files and settings from the backup and reboots it unless `--no-reboot` is passed.
Run restore only as a deliberate, separate step:

```sh
idevicebackup2 restore --system --settings -i ~/backups/iphone
```

`pymobiledevice3` is an actively developed alternative with selective backups:

```sh
nix shell nixpkgs#python3Packages.pymobiledevice3
pymobiledevice3 backup2 backup --full <dir>
```

## Tethering

For USB, pair once and enable Settings > Personal Hotspot.
The in-kernel `ipheth` driver exposes an ethernet interface that NetworkManager brings up automatically.
NCM support on kernel 6.5 and newer includes fixes for USB tethering drops and instability.
The cellular link is the bottleneck rather than USB.

Bluetooth PAN through blueman is an alternative.
The Wi-Fi hotspot behaves as a normal access point.

## Troubleshooting

- `idevice_id -l` prints nothing: replug, check `systemctl status usbmuxd`, and confirm the phone is unlocked.
- SSL or lockdownd connection errors: re-pair with `idevicepair unpair && idevicepair pair`.
- The file manager shows app folders but no `DCIM`: unlock the phone and re-pair to complete trust.
- `gphoto2` fails on permissions over SSH or from a unit: local seat access uses `uaccess`, while non-seat access requires the `camera` group.
  Log in again after the switch that adds the group.
- `gphoto2` cannot claim the USB device: GVfs's gphoto2 volume monitor holds the PTP port on detection, with or without a mount.
  Stop it with `systemctl --user stop gvfs-gphoto2-volume-monitor.service` and rerun the transfer.
- PTP listing fails after an iOS upgrade: libgphoto2 2.5.34 aborts with `GP_ERROR_FILE_EXISTS (-103)` on iOS 27 betas that repeat PTP filenames.
  Use the ifuse `DCIM` path for upstream libgphoto2 issue 1258.
- [USBGuard policy](../../modules/hosts/common/usbguard.nix) controls whether the service runs.
  If enabled, [allow the device](../security/usbguard/README.md) before usbmuxd can see it.
- Linux cannot sync into the native Music app because its protocol has not been reverse engineered.
  Use streaming or per-app drops through `ifuse --documents` into players that manage their own library.

## External references

<https://libimobiledevice.org/>, <https://wiki.archlinux.org/title/IOS>, <https://github.com/doronz88/pymobiledevice3>
