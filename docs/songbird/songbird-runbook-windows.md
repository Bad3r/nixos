# Songbird runbook: Windows

NixOS procedures are in [songbird-runbook.md](songbird-runbook.md).

## Boot Windows once from NixOS

Precondition: NixOS is running normally; resume a hibernated system instead of booting Windows over it.

1. Find the Windows boot entry:

   ```sh
   sudo efibootmgr
   ```

   Note the `Windows Boot Manager` entry number, for example `0002`.

2. Boot into it once:

   ```sh
   sudo efibootmgr --bootnext 0002 && systemctl reboot
   ```

   `--bootnext` boots Windows through its own firmware entry exactly once instead of chainloading via systemd-boot, which would change PCR 4 and trigger a BitLocker recovery prompt.

3. After Windows reorders the boot entries, restore the default:

   ```sh
   sudo efibootmgr -o <boot-order>
   ```

   Use the order `efibootmgr` reported in step 1, before Windows changed it.

Verification: the F8 firmware boot menu lists `Linux Boot Manager` first, and `efibootmgr` shows `BootNext` unset.

## Install Windows on disk W

Precondition: disk A is protected from the Windows installer, which drops its boot files onto the first ESP it finds.

1. Disable the M.2_1 slot in UEFI (Advanced > Onboard Devices), or remove disk A if the firmware offers no such toggle.

2. Boot the Windows installer, delete every partition on disk W, and install to the empty disk.

3. In an elevated shell, disable hibernation and Fast Startup, and set the hardware clock to UTC:

   ```sh
   powercfg /h off
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
   ```

   Windows never hibernates or fast-starts on this host, so disk W and `/portal` stay clean for every boot.

4. Enable BitLocker on drive C: with a password protector, and store the recovery key in the password manager.
   BitLocker warns that Secure Boot is off and binds to the PCR 0, 2, 4, 11 profile; that is the expected outcome with unsigned systemd-boot.

5. Re-enable or reinstall disk A, then in UEFI set `Linux Boot Manager` first in the boot order and `Windows Boot Manager` second.

Verification: both `Linux Boot Manager` and `Windows Boot Manager` boot cleanly from the F8 firmware boot menu.

## Convert portal to BitLocker

Precondition: `/portal` is the plain NTFS volume declared in `modules/songbird/hardware-config.nix`.

1. In Windows: back up the portal volume's contents, wipe it, and create a single GPT NTFS volume labeled `portal`.

2. Enable BitLocker on it with a password protector and a recovery key, then turn on autounlock:

   ```sh
   manage-bde -autounlock -enable <drive>:
   ```

   Store both the password and the recovery key in the password manager.

3. In NixOS, place the BitLocker password with no trailing newline at `/var/lib/secrets/portal-bitlk.key`, root owned, mode 0400.
   No module recreates this file, and it lives on disk A's root filesystem, which the reinstall procedure wipes; restore it from the password manager after every reinstall or `/portal` stays locked.

   A plain root-owned file replaces a sops runtime path because `systemd-cryptsetup@portal` runs from `cryptsetup.target`, before sops-nix activation writes `/run/secrets`.

4. Add the crypttab entry and point `/portal` at the mapped device in `modules/songbird/hardware-config.nix`:

   ```nix
   environment.etc."crypttab".text = ''
     portal /dev/disk/by-partuuid/<portal-partuuid> /var/lib/secrets/portal-bitlk.key bitlk,nofail
   '';
   ```

   Set `fileSystems."/portal".device` to `/dev/mapper/portal`.

Verification: reboot; `/portal` mounts owner-readable, and Windows still auto-unlocks it.
