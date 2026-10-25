# Guest shares

`workloads.guests.<name>.shares.<tag>` exports a host directory to a [declared guest](guests.md) over virtiofs.
The options and their defaults are documented in `modules/workloads/vms/options.nix`.

## Declare a share

Add the share to the guest declaration in `modules/hosts/<host>/workloads.nix`:

```nix
_: {
  configurations.nixos.<host>.module.workloads.guests.<name>.shares.<tag> = {
    hostPath = "<directory>";
    readOnly = true;
  };
}
```

- The tag names the share inside the guest.
- The directory is not created; a guest whose share directory is missing fails to start.
- The share assertions in `modules/workloads/vms/units.nix` and `modules/workloads/vms/windows/options.nix`, covered by the `workloads-vms-share-assertions` check, refuse shares on untrusted guests, root owners, and invalid tags.
  On Windows guests they also refuse a drive letter taken twice, and a `service` mode that cannot serve every share.
- A new or changed share applies at the guest's next cold boot: a running guest and a managed-save restore keep the old definition.
  A NixOS guest also needs a redeploy before its fstab follows, and a Windows guest's drive letters follow at its next start.

## How a share runs

libvirt starts one virtiofsd per share when the guest starts.
virtiofsd runs through a `setpriv` wrapper as the share's `owner` with its primary group, no supplementary groups, and no new privileges.
libvirt calls the wrapper at `/etc/workloads/virtiofsd-<owner>`, a path that survives switches and garbage collection.

- Guest root and the guest account with the owner's uid and gid write as the owner; any other guest uid or gid gets `Invalid argument`.
- `workloads-guest-base` pins the guest owner's uid to the host owner's.
- No guest account can do more in the directory than the owner's uid or primary group may; supplementary groups do not count.
- A `readOnly` share is refused by virtiofsd itself, so remounting it read-write in the guest changes nothing.
- A guest with any enabled share gets shared memfd memory, which virtiofs needs.
- Managed save and restore keep the shares working, live-attached ones included. A share removed while its guest is saved still restores when its owner is a normal user, since every normal user keeps a wrapper.

## NixOS guests

`workloads-guest-base` mounts the shares listed in `workloads.guest.shares` through fstab, with `nofail` and `ro` for read-only shares.
The guest configuration fills it from the derived `mounts` of its host declaration:

```nix
{ config, ... }:
{
  configurations.nixos.<name>.module.workloads.guest.shares =
    config.flake.nixosConfigurations.<host>.config.workloads.guests.<name>.mounts;
}
```

A share whose `mountPoint` clashes with another file system fails the guest's evaluation.

## Windows guests

`workloads-provision@<name>` gives every enabled share a drive letter at each start of a [Windows guest](windows.md).

- A share's `driveLetter` pins a letter from G to Z, since D to F stay free for the installation CD-ROMs.
  The others take the highest letters no other share pins, from Z down in tag order, so adding a share can move them.
  The read-only `windows.virtiofs.driveLetters` holds the result; other guest kinds ignore `driveLetter`.
- The host copies its pinned WinFsp installer in through the guest agent while the guest lacks that version or a newer one.
- The viofs driver and `virtiofs.exe` come with the virtio-win guest tools.
- virtio-win calls virtiofs on Windows a Tech Preview, in either mode.
- `windows.virtiofs.mode = "launcher"`, the default, keeps `VirtioFsSvc` disabled.
  The startup task `workloads-virtiofs` starts one WinFsp launcher instance of the `virtiofs` class per share, as SYSTEM.
- `windows.virtiofs.mode = "service"` mounts a single share, attached at boot, through `VirtioFsSvc`.
- Provisioning stops instances nothing declares, and removes the task once no share is left.
- When the set of attached shares changed since its last run, provisioning restarts every instance.

The drives belong to SYSTEM, so every session sees them, unless a mapped network drive on the same letter hides the share in that session.
In the guest, each launcher start appends its result to `C:\ProgramData\workloads\virtiofs.log`.

## Runtime shares

`runtime = true` keeps a share out of the definition, so it stays detached until attached to the running guest.
Its `<filesystem>` element is the derived `deviceXml` option, installed as `/etc/workloads/shares/<name>/<tag>.xml`.

1. Attach it as the owner, answering the admin prompt:

   ```sh
   virsh -c qemu:///system attach-device <name> /etc/workloads/shares/<name>/<tag>.xml --live
   ```

2. In a NixOS guest, the fstab entry is `noauto`, so mount it with `mount /mnt/<tag>`.
   In a Windows guest, restart provisioning, which restarts every launcher instance:

   ```sh
   sudo systemctl restart workloads-provision@<name>.service
   ```

`virsh -c qemu:///system detach-device <name> /etc/workloads/shares/<name>/<tag>.xml --live` removes it again after an unmount in the guest.
A Windows guest needs the same provisioning restart after a detach.
Each running `virtiofs.exe` remounts itself whenever any virtio-fs device arrives, which can break shares that are already mounted, until provisioning restarts them.

## Verify

As the owner on the host:

```sh
virsh -r -c qemu:///system dumpxml <name> | grep -A6 '<filesystem'
ps -o user=,args= -C virtiofsd
```

In a NixOS guest:

```sh
findmnt -t virtiofs
```

In an administrator PowerShell in a Windows guest:

```powershell
& "${env:ProgramFiles(x86)}\WinFsp\bin\launchctl-x64.exe" list
Get-PSDrive -PSProvider FileSystem
```

## A guest with a share fails to start

Cause: the share's directory is missing, or neither the owner's uid nor its primary group can reach it; supplementary groups do not count.

```sh
journalctl -u libvirtd.service -b | grep -i virtiofs
ls -ld <directory>
```

Fix: create the directory, give the owner's uid or primary group access to it, and start the guest again.
virtiofsd's own log is `/var/log/libvirt/qemu/<name>-fs<N>-virtiofsd.log`.

## A Windows share has no drive letter

Cause: another drive holds the letter, or the share's launcher instance exited.

```sh
journalctl -u workloads-provision@<name>.service -b
```

Fix: free the letter in the guest or set the share's `driveLetter`, then restart the unit:

```sh
sudo systemctl restart workloads-provision@<name>.service
```
