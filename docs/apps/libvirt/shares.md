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

- The tag names the share inside the guest; it matches `[a-z0-9][a-z0-9-]*` and has at most 36 characters.
- The directory is not created; a guest whose share directory is missing fails to start.
- Untrusted guests get no shares, and an assertion fails the build otherwise.
- `enable = false` drops a share without deleting its declaration.
- Shares follow the definition, so a new or changed share reaches a running guest at its next cold boot.

## How a share runs

libvirt starts one virtiofsd per share when the guest starts.
virtiofsd runs through a `setpriv` wrapper as the share's `owner` with its primary group, no supplementary groups, and no new privileges.

- Guest root and the guest account with the owner's uid write as the owner; any other guest account gets `Invalid argument`.
- No guest account can do more in the directory than the owner may.
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

A share mounts at `/mnt/<tag>` unless `mountPoint` names another path; `mountPoint = null` leaves it unmounted.

## Runtime shares

`runtime = true` keeps a share out of the definition, so it stays detached until attached to the running guest.
Its `<filesystem>` element is the derived `deviceXml` option.

1. Write the element to a file, from the repository root:

   ```sh
   nix eval --raw "path:.#nixosConfigurations.<host>.config.workloads.guests.<name>.shares.<tag>.deviceXml" > share.xml
   ```

2. Attach it as the owner, answering the admin prompt:

   ```sh
   virsh -c qemu:///system attach-device <name> share.xml --live
   ```

3. In a NixOS guest, the fstab entry is `noauto`, so mount it with `mount /mnt/<tag>`.

`virsh -c qemu:///system detach-device <name> share.xml --live` removes it again after an unmount in the guest.

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

Cause: the share's directory is missing, or its owner cannot reach it.

```sh
journalctl -u libvirtd.service -b | grep -i virtiofs
ls -ld <directory>
```

Fix: create the directory, give the owner access to it, and start the guest again.
virtiofsd's own log is `/var/log/libvirt/qemu/<name>-fs<N>-virtiofsd.log`.
