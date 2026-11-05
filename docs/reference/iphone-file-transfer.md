# iPhone file transfer

iOS never exposes mass storage.
USB access is limited to the media area (`DCIM`, `Downloads`, recordings), per-app Documents folders, and the read-only PTP camera roll.
[Pair the phone](iphone.md#pairing-and-trust) before accessing its files.

## File manager

After pairing, a GVfs-capable file manager shows a documents (AFC) volume and a camera (gphoto2) volume.
Select the default through `host.defaults.fileManager` in [default-apps.nix](../../modules/hosts/common/default-apps.nix).
The manager catalog and its metadata live in [mime.nix](../../modules/xdg/mime.nix).
Browsing through GVfs is the slowest path; use it for browsing, not bulk copies.

## Bulk copies with ifuse and rsync

```sh
mkdir -p ~/mnt/iphone
ifuse ~/mnt/iphone
rsync -av --partial --progress ~/mnt/iphone/DCIM/ ~/Pictures/iphone/
fusermount3 -u ~/mnt/iphone
```

AFC is protocol-bound at roughly 2-20 MB/s reads and often 1-2 MB/s writes, regardless of USB 2 or USB 3 hardware.
Long imports can hit an AFC idle disconnect, a known upstream libimobiledevice issue.
Remount and rerun rsync, which resumes the interrupted file rather than recopying it.
Without `--partial`, rsync discards the in-flight temporary file.

## Per-app documents

```sh
ifuse --list-apps
ifuse --documents <bundle-id> ~/mnt/iphone
```

Only apps that opt into file sharing are mountable.

## Camera roll over PTP

```sh
gphoto2 --auto-detect
gphoto2 --get-all-files --filename '%Y%m%d-%H%M%S-%n.%C'
gphoto2 --new --get-all-files
```

Keep the phone unlocked for the whole transfer and accept the photo-access prompt.
HEIC/HEVC files transfer as-is.

PTP goes through libusb rather than usbmuxd.
Stock systemd `70-uaccess.rules` tags USB devices exposing the PTP interface class for `uaccess`.
`73-seat-late.rules` grants access to the active local seat.
[The gphoto2 module](../../modules/apps/gphoto2.nix) installs libgphoto2's rules, providing the `ID_GPHOTO2` property GVfs uses to offer the camera volume.
Those rules also allow the `camera` group to reach the device outside the local seat, such as over SSH.
That group reaches a session only at login.

## Network transfers

- LocalSend works for everyday-sized files in both directions but has no transfer resume.
  A 120 GiB ZIP transfer fails, so avoid LocalSend for very large files.
- The iOS Files app has a built-in SMB client under Connect to Server that mounts LAN shares at Wi-Fi speed.

## Very large files

No iOS transport moves a 100 GiB-class file reliably in one piece.
LocalSend fails, Files-app SMB copies cannot resume, and iOS suspends app-driven transfers when the screen locks.
Chunk first so a failed transfer can be retried per part:

```sh
split -b 4G huge.zip huge.zip.part-
sha256sum huge.zip.part-* > SHA256SUMS
# after transfer: sha256sum -c SHA256SUMS && cat huge.zip.part-* > huge.zip
```

- Phone to computer over USB: `ifuse` plus `rsync --partial --progress` resumes across AFC idle disconnects.
  Remount and rerun after a disconnect.
- Either direction over Wi-Fi: copy parts through SMB with the phone awake, or use an SFTP/WebDAV server app and rclone from the computer.
  Rclone retries per chunk.
- Computer to phone over USB: AFC writes at 1-2 MB/s take roughly a day for 100 GiB.
  Prefer a network path in that direction.

[Connection and transfer failures](iphone.md#troubleshooting)
