# Songbird troubleshooting: Windows

NixOS entries are in [songbird-troubleshooting.md](songbird-troubleshooting.md).

## /portal is missing after boot

An unclean Windows exit leaves the shared NTFS volume dirty, so the kernel `ntfs3` driver refuses it, and `nofail` on `/portal` in `modules/songbird/hardware-config.nix` lets boot continue anyway.

```sh
journalctl -b -u portal.mount
```

Boot Windows once through [songbird-runbook-windows.md](songbird-runbook-windows.md) and shut it down cleanly; Windows replays the journal on mount and clears the flag on shutdown.
Clear the flag directly only when Windows is unreachable, since `ntfsfix -d` discards the pending journal instead of replaying it.

```sh
sudo ntfsfix -d /dev/disk/by-id/nvme-Samsung_SSD_970_PRO_512GB_S469NF0K509254D-part1
sudo systemctl start portal.mount
```

## Hibernation fails while /portal is open

`modules/songbird/hardware-config.nix` unmounts `/portal` before hibernating on purpose, and a process holding it open fails that unmount, so the transition aborts instead of corrupting the volume.

```sh
fuser -vm /portal
```

Close whatever holds `/portal` open, then retry the hibernate or suspend command.

## Windows Boot Manager boots by default

A Windows feature update can rewrite the UEFI boot order and place its own entry ahead of the Linux one.

```sh
efibootmgr
```

Reorder with `sudo efibootmgr -o`, listing the Linux Boot Manager entry first.

## BitLocker asks for the recovery key

A BIOS update can reset the Intel PTT firmware TPM, changing the measured values BitLocker checks before it unlocks automatically.

```sh
cat /sys/class/dmi/id/bios_version
```

Enter the recovery key from the password manager once; the machine boots normally afterward.
