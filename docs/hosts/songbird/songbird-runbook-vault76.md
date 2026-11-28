# Songbird runbook: vault76 volume

- [songbird-configuration.md](songbird-configuration.md)
- [songbird-runbook-reinstall.md](songbird-runbook-reinstall.md)

The `vault76` LUKS2 volume on disk W holds XFS and opens only on demand, as [vault76.nix](../../../modules/hosts/songbird/vault76.nix) declares.
Key slot 0 holds a passphrase distinct from root's.
Two more slots each hold a FIDO2 enrollment of one YubiKey, which unlocks with the key's FIDO2 PIN and a touch.
No keyfile and no recovery key exist, so losing the passphrase and both YubiKeys loses the data.
The header backup lives offline.
The volume has no snapshots and no second copy, so a deleted file is gone.
The `discard` mount option trims a deleted file's blocks at once.
TRIM through LUKS shows which blocks are in use to anyone holding the drive, without revealing their contents.
The empty mount point `/srv/vault76` carries `chattr +i`, so nothing lands on root while the volume is locked.
The nightly `updatedb` skips `/srv/vault76`, so the locate database on root holds no file name from the volume.

## Unlock and mount

Precondition: `vault76 status` reports vault76 locked.

1. Plug in one enrolled YubiKey, then unlock:

   ```sh
   sudo vault76 unlock
   ```

2. Enter the YubiKey's FIDO2 PIN at the prompt and touch the key when it blinks.

`vault76 unlock` starts `srv-vault76.mount`, which pulls in `systemd-cryptsetup@vault76.service`.
With no enrolled YubiKey plugged in, it asks for the passphrase after 30 seconds.
The command refuses when the drive is not attached.

Verification: `findmnt /srv/vault76` shows `/dev/mapper/vault76` as `xfs` with `discard`.

## Lock the volume

```sh
sudo vault76 lock
```

The lock refuses while a process holds a file or its working directory on `/srv/vault76`, and it names those processes.

Verification: `vault76 status` reports vault76 locked, and `/dev/mapper/vault76` is absent.

## Auto-lock

`vault76-autolock.service` starts with every mount of `/srv/vault76`.
It locks the volume after 90 minutes without a read or write on `/dev/mapper/vault76`.
It counts the device's completed reads and writes, so a file served from the page cache is no activity.
One minute before the lock, a critical notification appears on the owner's desktop.
Middle-click it, or read or write the drive, to keep vault76 unlocked for another full period.
Closing the notification any other way keeps the lock.
While a process holds the volume, the lock waits, a notification names the holders, and the volume locks once they let go.
When nobody is logged in to a desktop, the lock goes ahead without a notice.
Stopping `srv-vault76.mount` alone also closes `/dev/mapper/vault76`.

Change the period for the open session; it holds until the next lock:

```sh
sudo vault76 unlock --timeout=off
sudo vault76 unlock --timeout=45m
```

`--timeout` takes `off` or minutes and hours such as `45m`, `1h` or `1h30m`, at least `2m`.
On an unlocked volume, `vault76 unlock --timeout=...` changes the period and restarts the idle clock.
The default lives in [vault76.nix](../../../modules/hosts/songbird/vault76.nix) as `autolockMinutes`.

Verification: `vault76 status` shows the period and the idle time, and `journalctl -u vault76-autolock` logs the warning and the lock.

## Replace a lost YubiKey

Precondition: one enrolled YubiKey is lost or broken, and a new YubiKey has a FIDO2 PIN set.

1. Plug in only the YubiKey you still have, enroll it again, and wipe every other FIDO2 slot, the lost key's included:

   ```sh
   sudo systemd-cryptenroll /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1 --wipe-slot=fido2 --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes
   ```

   The command asks for the passphrase, then the YubiKey's PIN and a touch.
   It wipes only after the new enrollment succeeds.

2. Plug in only the new YubiKey and enroll it:

   ```sh
   sudo systemd-cryptenroll /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1 --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes
   ```

3. Refresh the header backup as the next section describes, since the key slots changed.

Verification: `sudo systemd-cryptenroll /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1` lists one `password` slot and two `fido2` slots, and each YubiKey unlocks the volume on its own.

## Refresh the header backup

Precondition: a key slot was added, removed, or changed.

1. Write and check a new backup:

   ```sh
   sudo cryptsetup luksHeaderBackup /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1 --header-backup-file /root/vault76-hdr.img
   sudo cryptsetup open --test-passphrase --key-slot 0 --header /root/vault76-hdr.img /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1
   sudo sha256sum /root/vault76-hdr.img
   ```

   The test prompt takes the passphrase.

2. Copy the file to two offline media in separate places and compare the hash on each.

3. Delete `/root/vault76-hdr.img` and destroy every older backup, since an old header keeps a removed key slot valid.

Verification: `cryptsetup luksDump` of each copy lists the same key slots as the live header.

## Erase the volume for good

Precondition: nothing on the volume is to be kept.

1. Erase the volume:

   ```sh
   sudo vault76 wipe
   ```

   It names the partition and its key slots, then asks to type `vault76`; `--force` skips the question.
   It locks the volume first and refuses while a process holds it.
   It then erases every key slot with `cryptsetup luksErase` and checks that none is left.
   Last, `blkdiscard -z` zero-fills the whole LUKS partition, header and encrypted data alike.
   A header backup opens nothing afterwards.
   The partition table stays.

2. Destroy every copy of the header backup.

3. Remove [vault76.nix](../../../modules/hosts/songbird/vault76.nix), switch to the new generation, and remove the mount point with `sudo chattr -i /srv/vault76 && sudo rmdir /srv/vault76`.

Verification: `sudo cryptsetup isLuks /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1` fails.

## Check the volume

- `systemctl --failed` listing `systemd-cryptsetup@vault76.service` or `srv-vault76.mount` after a start means the volume did not open or mount.
- `ykman fido info` shows a YubiKey's remaining PIN retries; when they run out, the key's FIDO2 function stays blocked until a reset, and a reset destroys its `vault76` enrollment.
- XFS checksums its metadata only, so a damaged file can read back wrong without an error.
- `sudo nvme smart-log /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492` reports `critical_warning` and `media_errors` at 0 on a healthy drive.
