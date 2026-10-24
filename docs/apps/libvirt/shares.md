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
- The share assertions in `modules/workloads/vms/units.nix`, covered by the `workloads-vms-share-assertions` check, refuse shares on untrusted guests, root owners, and invalid tags.
- A new or changed share applies at the guest's next cold boot: a running guest and a managed-save restore keep the old definition.
  A NixOS guest also needs a redeploy before its fstab follows.

## How a share runs

libvirt starts one virtiofsd per share when the guest starts.
virtiofsd runs through a `setpriv` wrapper as the share's `owner` with its primary group, no supplementary groups, and no new privileges.
libvirt calls the wrapper at `/etc/workloads/virtiofsd-<owner>`, a path that survives switches and garbage collection.

- Guest root and the guest account with the owner's uid and gid write as the owner; any other guest uid or gid gets `Invalid argument`.
- `workloads-guest-base` pins the guest owner's uid to the host owner's.
- No guest account can do more in the directory than the owner's uid or primary group may; supplementary groups do not count.
- A `readOnly` share is refused by virtiofsd itself, so remounting it read-write in the guest changes nothing.
- A guest with any enabled share gets shared memfd memory, which virtiofs needs.
- Managed save and restore keep the shares working, live-attached ones included.

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

## Runtime shares

`runtime = true` keeps a share out of the definition, so it stays detached until attached to the running guest.
Its `<filesystem>` element is the derived `deviceXml` option, installed as `/etc/workloads/shares/<name>/<tag>.xml`.

1. Attach it as the owner, answering the admin prompt:

   ```sh
   virsh -c qemu:///system attach-device <name> /etc/workloads/shares/<name>/<tag>.xml --live
   ```

2. In a NixOS guest, the fstab entry is `noauto`, so mount it with `mount /mnt/<tag>`.

`virsh -c qemu:///system detach-device <name> /etc/workloads/shares/<name>/<tag>.xml --live` removes it again after an unmount in the guest.

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

## A guest with a share fails to start

Cause: the share's directory is missing, or neither the owner's uid nor its primary group can reach it; supplementary groups do not count.

```sh
journalctl -u libvirtd.service -b | grep -i virtiofs
ls -ld <directory>
```

Fix: create the directory, give the owner's uid or primary group access to it, and start the guest again.
virtiofsd's own log is `/var/log/libvirt/qemu/<name>-fs<N>-virtiofsd.log`.
