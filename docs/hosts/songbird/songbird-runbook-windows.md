# Songbird runbook: Windows

- [songbird-runbook.md](songbird-runbook.md)
- [songbird-runbook-reinstall.md](songbird-runbook-reinstall.md)

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

   `--bootnext` boots Windows through its own firmware entry exactly once.
   Chainloading through systemd-boot instead would change PCR 4 and trigger a BitLocker recovery prompt.

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

## Move Windows Boot Manager to disk W

Precondition: Windows boots through the `Windows Boot Manager` firmware entry, disk W has no `EFI System` partition, and the C: recovery key is in the password manager.

1. Boot Windows once as in [Boot Windows once from NixOS](#boot-windows-once-from-nixos), then suspend BitLocker on C: in an elevated shell until step 7 resumes it:

   ```sh
   manage-bde -protectors -disable C: -RebootCount 0
   ```

2. In an elevated `diskpart`, find disk W's number with `list disk` (the 953 GB disk), then shrink C: and create an ESP in the freed space:

   ```sh
   select volume C
   shrink desired=300
   select disk <disk-w-number>
   create partition efi size=260
   format quick fs=fat32 label=SYSTEM
   assign letter=S
   exit
   ```

3. Copy the boot files and a new BCD store onto the ESP, then remove its drive letter:

   ```sh
   bcdboot C:\Windows /s S: /f UEFI
   mountvol S: /d
   ```

   With `/s`, `bcdboot` writes no firmware entry, so NixOS creates it in step 5.

4. Reboot into NixOS and read the ESP's partition number on disk W:

   ```sh
   lsblk -o NAME,PARTTYPENAME /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492
   ```

5. Note the current `Windows Boot Manager` entry number in `efibootmgr` as `<old-windows-entry>`.
   Create a firmware entry on disk W's ESP, then set the order to `Linux Boot Manager`, the new entry, and the remaining entries:

   ```sh
   sudo efibootmgr --create-only --disk /dev/disk/by-id/nvme-WDC_PC_SN720_SDAQNTW-1T00-1001_192461421492 --part <esp-partition-number> --label 'Windows Boot Manager' --loader '\EFI\Microsoft\Boot\bootmgfw.efi'
   sudo efibootmgr --bootorder <linux-entry>,<new-windows-entry>,<remaining-entries>
   ```

   The old entry stays as a fallback until step 6 boots Windows through the new one.

6. Boot Windows through the new entry:

   ```sh
   sudo efibootmgr --bootnext <new-windows-entry> && systemctl reboot
   ```

7. In an elevated shell, resume BitLocker and register the recovery environment in the new BCD store:

   ```sh
   manage-bde -protectors -enable C:
   reagentc /disable
   reagentc /enable
   ```

8. Back in NixOS, confirm `<old-windows-entry>`: its `Windows Boot Manager` line in `efibootmgr -v` carries disk A's ESP PARTUUID, which this prints:

   ```sh
   findmnt -no PARTUUID /boot
   ```

   Delete that entry, remove the old boot files from disk A's ESP, and put `Linux Boot Manager` first again, since booting Windows reorders the entries:

   ```sh
   sudo efibootmgr --bootnum <old-windows-entry> --delete-bootnum
   sudo rip /boot/EFI/Microsoft
   sudo efibootmgr --bootorder <linux-entry>,<new-windows-entry>,<remaining-entries>
   ```

   Removing the boot files also drops the Windows entry from the systemd-boot menu.

Verification:

- `efibootmgr -v` shows `Windows Boot Manager` only on the PARTUUID that `lsblk -o NAME,PARTUUID` reports for disk W's ESP.
- `efibootmgr` shows `BootOrder` starting with the `Linux Boot Manager` entry.
- In Windows, `manage-bde -status C:` reports `Protection On`, and `reagentc /info` reports `Enabled`.
