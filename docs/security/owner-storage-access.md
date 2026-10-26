# Owner storage device access

The owner profile in `modules/meta/owner.nix` assigns no group that opens a block device, an NVMe controller node, or an NVMe generic node.
Every tool that touches those nodes runs under `sudo`.

## Why `disk` stays unassigned

- The default udev rules make every block device `root:disk 0660`: the decrypted root, `/data`, swap, the unencrypted `/boot`, and the raw LUKS partitions.
- A `disk` member reads any file offline from those nodes, including `/etc/shadow`, the SSH host keys, and the sops age key.
- Write access adds tampering with `/boot` and destroying a LUKS header.
- Read-only access is no narrower, because a raw read alone exposes every secret on the filesystem.

## Why NVMe controller nodes stay root-only

- `/dev/nvmeN` and `/dev/ngNnM` keep the kernel default `root:root 0600`, and no rule in the repository regroups them.
- On a controller with exactly one namespace, `NVME_IOCTL_IO_CMD` on `/dev/nvmeN` forwards I/O commands to that namespace through `nvme_dev_user_cmd()`.
- `nvme_ns_cmd_allowed()` then admits a Read without `CAP_SYS_ADMIN` when the controller's effects log marks it supported, and a Write when the node is open for writing.
- A generic node `/dev/ngNnM` takes the same I/O passthrough by design.
- A group on either node class is therefore a raw-read grant on the drive, so no dedicated diagnostics group exists.
- Capability wrappers gain nothing: without `CAP_DAC_OVERRIDE` they cannot open a root-only node, and with it they become a raw-read path.

Kernel source: [drivers/nvme/host/ioctl.c at v7.3](https://github.com/torvalds/linux/blob/v7.3/drivers/nvme/host/ioctl.c)

## Commands

- Unprivileged:
  - `lsblk`, `findmnt`, and `nvme list`, which read sysfs and the udev database without opening a device node.
- Under `sudo`:
  - `fdisk`, `parted`, and probing `blkid`.
  - `smartctl`, `hdparm`, `sedutil-cli`, and every `nvme` subcommand that opens a device node.

## After a switch

Supplementary groups are set at login, so every process started before the switch keeps `disk` until it exits.
That includes the user service manager, which outlives a single session while another one stays open.
Existing NVMe controller and generic nodes keep their `root:disk 0660` mode until the next boot, because udev applies rule changes only to new events.
No login user is in `disk` after that re-login, so the stale mode grants nothing.
System units that run owner processes, such as the `r2-mount-*` FUSE mounts, keep `disk` across a re-login, because a switch restarts only units whose unit file changed.

1. End every owner session, local and SSH, and stop any process that outlives logout, such as a tmux server.

2. Log back in and confirm that `loginctl user-status "$USER"` lists only the new session.

3. Restart the system services whose owner processes still hold `disk`, such as the R2 mounts; the filter skips scopes, which cannot restart, and `user@.service`, which step 2 recycles:

   ```sh
   ps -u "$USER" -o unit=,supgrp= | grep -w disk |
     awk '$1 ~ /\.service$/ && $1 !~ /^user@/ {print $1}' | sort -u |
     xargs -r sudo systemctl restart
   ```

4. Check the result with the commands below.

## Verification

- `id -nG`
  - should not list `disk`.
- `getent group disk`
  - should end in an empty member list.
- `ps -u "$USER" -o supgrp= | grep -cw disk`
  - should print `0`.
- `ls /run/wrappers/bin`
  - should list none of `smartctl`, `nvme`, `hdparm`, or `sedutil-cli`.
- `head -c 1 /dev/nvme0n1 >/dev/null`
  - should fail with `Permission denied`.
- `ls -l /dev/nvme0 /dev/ng0n1`
  - should show `root root` with mode `crw-------` after the next boot.
