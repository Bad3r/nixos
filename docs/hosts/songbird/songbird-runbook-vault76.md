# Songbird runbook: vault76 volume

- [songbird-configuration.md](songbird-configuration.md)
- [songbird-runbook-reinstall.md](songbird-runbook-reinstall.md)

The `vault76` LUKS2 volume on disk W holds XFS and opens in stage 2, as [vault76.nix](../../../modules/hosts/songbird/vault76.nix) declares.
Key slot 0 holds a passphrase distinct from root's, slot 1 the keyfile `/etc/cryptsetup-keys.d/vault76.key` on the encrypted root, and slot 2 a systemd recovery key.
The passphrase, the recovery key, and the header backup live offline.
The volume has no snapshots and no second copy, so a deleted file is gone.
The `discard` mount option trims a deleted file's blocks at once.
TRIM through LUKS shows which blocks are in use to anyone holding the drive, without revealing their contents.
The empty mount point `/srv/vault76` carries `chattr +i`, so nothing lands on root while the volume is absent.

## Mount the volume by hand

Precondition: disk W was absent or locked at boot, so `systemctl status srv-vault76.mount` shows it inactive.

```sh
sudo systemctl start srv-vault76.mount
```

The mount pulls in `systemd-cryptsetup@vault76.service`, which reads the keyfile, or asks for the passphrase when the keyfile is missing.

Verification: `findmnt /srv/vault76` shows `/dev/mapper/vault76` as `xfs` with `discard`.

## Replace the keyfile after a reinstall

Precondition: a reinstall wiped disk A's root filesystem, so the keyfile is gone and `vault76` asks for its passphrase at boot.

1. Create a new keyfile:

   ```sh
   sudo install -d -m 0700 /etc/cryptsetup-keys.d
   sudo sh -c 'umask 077; head -c 512 /dev/urandom > /etc/cryptsetup-keys.d/vault76.key'
   sudo chmod 0400 /etc/cryptsetup-keys.d/vault76.key
   ```

2. Drop the lost keyfile's slot, then enrol the new one, authenticating both times with the passphrase:

   ```sh
   sudo cryptsetup luksKillSlot /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1 1
   sudo cryptsetup luksAddKey /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1 /etc/cryptsetup-keys.d/vault76.key
   ```

3. Refresh the header backup as the next section describes, since the key slots changed.

Verification: reboot; `/srv/vault76` mounts with no passphrase prompt.

## Refresh the header backup

Precondition: a key slot was added, removed, or changed.

1. Write and check a new backup:

   ```sh
   sudo cryptsetup luksHeaderBackup /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1 --header-backup-file /root/vault76-hdr.img
   sudo cryptsetup open --test-passphrase --header /root/vault76-hdr.img /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1
   sudo sha256sum /root/vault76-hdr.img
   ```

   The test prompt takes the passphrase; run it once more with the recovery key.

2. Copy the file to two offline media in separate places and compare the hash on each.

3. Delete `/root/vault76-hdr.img` and every older backup, since an old header keeps a removed key slot valid.

Verification: `cryptsetup luksDump` of each copy lists the same key slots as the live header.

## Erase the volume for good

Precondition: nothing on the volume is to be kept.

1. Unmount the volume, close it, and erase every key slot:

   ```sh
   sudo umount /srv/vault76
   sudo cryptsetup close vault76
   sudo cryptsetup luksErase /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1
   ```

   `luksErase` asks for confirmation and removes the volume key; the encrypted data stays on the disk, and no key opens it.
   `sudo cryptsetup luksDump /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492-part1` then lists no key slots.

2. Destroy every copy of the header backup and delete `/etc/cryptsetup-keys.d/vault76.key`, since a header backup restores the erased key slots.

3. Remove [vault76.nix](../../../modules/hosts/songbird/vault76.nix), switch to the new generation, and remove the mount point with `sudo chattr -i /srv/vault76 && sudo rmdir /srv/vault76`.

4. To make the drive drop the encrypted blocks as well, discard the whole disk:

   ```sh
   sudo blkdiscard -f /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492
   ```

## Check the volume

- `systemctl --failed` listing `systemd-cryptsetup@vault76.service` or `srv-vault76.mount` means the volume did not open or mount.
- XFS checksums its metadata only, so a damaged file can read back wrong without an error.
- `sudo nvme smart-log /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492` reports `critical_warning` and `media_errors` at 0 on a healthy drive.
