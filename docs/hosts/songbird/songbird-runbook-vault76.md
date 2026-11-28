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

## Unlock and mount

Precondition: `systemctl status srv-vault76.mount` shows it inactive.

1. Plug in one enrolled YubiKey, then start the mount:

   ```sh
   sudo systemctl start srv-vault76.mount
   ```

2. Enter the YubiKey's FIDO2 PIN at the prompt and touch the key when it blinks.

The mount pulls in `systemd-cryptsetup@vault76.service`.
With no enrolled YubiKey plugged in, it asks for the passphrase after 30 seconds.

Verification: `findmnt /srv/vault76` shows `/dev/mapper/vault76` as `xfs` with `discard`.

## Lock the volume

```sh
sudo systemctl stop srv-vault76.mount systemd-cryptsetup@vault76.service
```

Verification: `/dev/mapper/vault76` is absent.

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

1. Lock the volume as described above, then erase every key slot:

   ```sh
   sudo cryptsetup luksErase /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1
   ```

   `luksErase` asks for confirmation and removes the volume key; the encrypted data stays on the disk, and no key opens it.
   `sudo cryptsetup luksDump /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1` then lists no key slots.

2. Destroy every copy of the header backup, since a header backup restores the erased key slots.

3. Remove [vault76.nix](../../../modules/hosts/songbird/vault76.nix), switch to the new generation, and remove the mount point with `sudo chattr -i /srv/vault76 && sudo rmdir /srv/vault76`.

4. To make the drive drop the encrypted blocks as well, discard the whole disk:

   ```sh
   sudo blkdiscard -f /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492
   ```

## Check the volume

- `systemctl --failed` listing `systemd-cryptsetup@vault76.service` or `srv-vault76.mount` after a start means the volume did not open or mount.
- `ykman fido info` shows a YubiKey's remaining PIN retries; when they run out, the key's FIDO2 function stays blocked until a reset, and a reset destroys its `vault76` enrollment.
- XFS checksums its metadata only, so a damaged file can read back wrong without an error.
- `sudo nvme smart-log /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492` reports `critical_warning` and `media_errors` at 0 on a healthy drive.
