# Songbird runbook: portal

- [songbird-runbook-windows.md](songbird-runbook-windows.md)
- [songbird-troubleshooting-windows.md](songbird-troubleshooting-windows.md)

## Convert portal to BitLocker

Precondition: `/portal` is the plain NTFS volume declared in `modules/hosts/songbird/hardware-config.nix`.

1. In Windows: back up the portal volume's contents, wipe it, and create a single GPT NTFS volume labeled `portal`.

2. Enable BitLocker on it with a password protector and a recovery key, then turn on autounlock:

   ```sh
   manage-bde -autounlock -enable <drive>:
   ```

   Store both the password and the recovery key in the password manager.

3. In NixOS, place the BitLocker password with no trailing newline at `/var/lib/secrets/portal-bitlk.key`, root owned, mode 0400.
   No module recreates the key file, and the reinstall procedure wipes disk A's root filesystem that holds it.
   Restore it from the password manager after every reinstall, or `/portal` stays locked.

   A plain root-owned file replaces a sops runtime path because `systemd-cryptsetup@portal` runs from `cryptsetup.target`, before sops-nix activation writes `/run/secrets`.

4. Add the crypttab entry and point `/portal` at the mapped device in `modules/hosts/songbird/hardware-config.nix`:

   ```nix
   environment.etc."crypttab".text = ''
     portal /dev/disk/by-partuuid/<portal-partuuid> /var/lib/secrets/portal-bitlk.key bitlk,nofail
   '';
   ```

   Set `fileSystems."/portal".device` to `/dev/mapper/portal`.

Verification: reboot; `/portal` mounts owner-readable, and Windows still auto-unlocks it.
