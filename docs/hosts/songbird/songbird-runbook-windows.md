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
