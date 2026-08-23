# iPhone Support

Apple ships no iOS tooling for Linux; everything below runs on the
community stack (libimobiledevice 1.4.0 era, current as of 2026-08).
The moving parts in this repo:

- `modules/apps/usbmuxd.nix`: the pairing daemon
  (`services.usbmuxd.extended`), required by every USB path including
  tethering trust.
- `modules/apps/libimobiledevice.nix`: `idevicepair`, `ideviceinfo`,
  `idevicebackup2`, `afcclient`, `idevicesyslog`.
- `modules/apps/ifuse.nix`: FUSE mounts of the media filesystem and
  per-app Documents folders.
- `modules/apps/gphoto2.nix`: scriptable PTP camera-roll import.
- Already present: the gvfs AFC and gphoto2 backends
  (`services.gvfs` in `modules/hosts/common/services.nix`) and
  LocalSend (`modules/apps/localsend.nix`, port 53317).

All are enabled in the common baseline
(`modules/hosts/common/apps-enable.nix`); per-host `appEnable`
overrides can opt out, but `libimobiledevice` and `ifuse` assert that
the usbmuxd daemon stays enabled.

## Pairing And Trust

Connect with a data-capable cable, unlock the phone, then:

```sh
idevicepair pair      # accept the trust dialog on the phone, run again
idevicepair validate
ideviceinfo -k ProductVersion
```

Major iOS upgrades can invalidate the stored pair record. When
lockdownd starts refusing connections, reset it:

```sh
idevicepair unpair && idevicepair pair
```

## File Transfer

iOS never exposes mass storage. USB access is limited to the media
area (`DCIM`, `Downloads`, recordings), per-app Documents folders, and
the read-only PTP camera roll.

### File manager (casual)

After pairing, the device appears in PCManFM/Nemo through gvfs with a
documents (AFC) and a camera (gphoto2) volume. This is the slowest
path; use it for browsing, not bulk copies.

### Bulk copies (ifuse + rsync)

```sh
mkdir -p ~/mnt/iphone
ifuse ~/mnt/iphone
rsync -av --progress ~/mnt/iphone/DCIM/ ~/Pictures/iphone/
fusermount3 -u ~/mnt/iphone
```

Expectations: AFC is protocol-bound at roughly 2-20 MB/s reads and
often 1-2 MB/s writes, regardless of USB 2 or USB 3 hardware. Long
imports can hit an AFC idle disconnect (known upstream
libimobiledevice issue); remount and rerun rsync, which resumes where
it stopped.

### Per-app documents

```sh
ifuse --list-apps
ifuse --documents <bundle-id> ~/mnt/iphone
```

Only apps that opt into file sharing are mountable.

### Camera roll over PTP (gphoto2)

```sh
gphoto2 --auto-detect
gphoto2 --get-all-files --filename '%Y%m%d-%H%M%S-%n.%C'
gphoto2 --new --get-all-files
```

Keep the phone unlocked for the whole transfer and accept the
photo-access prompt. HEIC/HEVC files transfer as-is.

PTP goes through libusb rather than usbmuxd, so it needs libgphoto2's
own udev rules. `modules/apps/gphoto2.nix` installs them and adds the
owner to the `camera` group those rules hardcode. Neither `gvfs` nor
`usbmuxd` supplies them. After the first `nixos-rebuild switch` that
lands this, log out and back in; until the new group is in the
session, every `gphoto2` device command fails as an ordinary user.

### Fast paths over the network

- LocalSend (already enabled) works well for everyday-sized files in
  both directions, but it has no transfer resume and fails outright
  on 100 GiB-class archives (observed with a 120 GiB zip). Do not
  use it for very large files.
- The iOS Files app has a built-in SMB client (Connect to Server)
  that mounts any LAN SMB share at Wi-Fi speed.

### Very large files (tens of GiB and up)

No iOS transport moves a 100 GiB-class file reliably in one piece:
LocalSend fails, Files-app SMB copies cannot resume, and iOS
suspends app-driven transfers when the screen locks. Chunk first;
then any transport works and every failure is retryable per part:

```sh
split -b 4G huge.zip huge.zip.part-
sha256sum huge.zip.part-* > SHA256SUMS
# after transfer: sha256sum -c SHA256SUMS && cat huge.zip.part-* > huge.zip
```

- Phone to computer over USB: `ifuse` plus
  `rsync --partial --progress` resumes across AFC idle disconnects
  (remount and rerun).
- Either direction over Wi-Fi: copy the parts through the SMB share
  with the phone kept awake, or run an SFTP/WebDAV server app on the
  phone and drive the copy with rclone from the computer, which
  retries per chunk.
- Computer to phone over USB is the worst case: AFC writes run at
  1-2 MB/s, roughly a day for 100 GiB. Prefer a network path in that
  direction.

## Backup

```sh
idevicebackup2 encryption on
idevicebackup2 backup --full ~/backups/iphone
```

Prefer encrypted backups: they include health and keychain data that
unencrypted backups omit. The `list` subcommand is broken upstream.
Full backups of a large phone take hours at AFC-class throughput.
`backup --full` updates the existing set under `<dir>/<udid>/` in
place rather than writing a new dated copy.

NOTE: `restore --system --settings` overwrites the phone's current
system files and settings from this backup and reboots the device
when done; upstream reboots unless `--no-reboot` is passed. Run it
only as a deliberate, separate step, never pasted with the backup
above.

```sh
idevicebackup2 restore --system --settings ~/backups/iphone
```

`pymobiledevice3` is the actively developed alternative, including
selective backups:

```sh
nix shell nixpkgs#python3Packages.pymobiledevice3
pymobiledevice3 backup2 backup --full <dir>
```

## Tethering

USB: pair once, enable Settings > Personal Hotspot, and the in-kernel
`ipheth` driver exposes an ethernet interface NetworkManager brings up
automatically. NCM support (kernel 6.5 onward, with fixes through
current kernels) removed the historic drop/instability problems; the
cellular link, not USB, is the bottleneck. Bluetooth PAN via blueman
is a workable alternative, and the Wi-Fi hotspot behaves as a normal
access point.

## Troubleshooting

- `idevice_id -l` prints nothing: replug, check
  `systemctl status usbmuxd`, confirm the phone is unlocked.
- SSL or lockdownd connection errors: re-pair with
  `idevicepair unpair && idevicepair pair`.
- File manager shows app folders but no `DCIM`: trust is incomplete;
  unlock the phone and re-pair.
- `gphoto2` fails on permissions for an ordinary user: the `camera`
  group is not in the current session; log out and back in after the
  rebuild that first installs the libgphoto2 udev rules.
- `gphoto2` reports it cannot claim the USB device: gvfs's gphoto2
  volume monitor holds the PTP port on detection, with or without a
  mount; stop it and rerun the transfer with
  `systemctl --user stop gvfs-gphoto2-volume-monitor.service`.
- PTP listing fails after an iOS upgrade: libgphoto2 2.5.34 aborts
  the folder listing with `GP_ERROR_FILE_EXISTS (-103)` on iOS 27
  betas, which repeat PTP filenames (upstream libgphoto2 issue 1258,
  open as of 2026-08); use the ifuse `DCIM` path meanwhile.
- USBGuard is force-disabled in `modules/hosts/common/usbguard.nix`.
  If it is ever re-enabled, allow the device per
  `docs/usbguard/README.md` before usbmuxd can see it.
- Music sync into the native Music app is not possible from Linux;
  that protocol was never reverse engineered. Use streaming or
  per-app drops (`ifuse --documents`) into players that manage their
  own library.

## External References

- `https://libimobiledevice.org/`
- `https://wiki.archlinux.org/title/IOS`
- `https://github.com/doronz88/pymobiledevice3`
