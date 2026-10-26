# Runtime shares

`workloads share attach` hot-plugs a declared virtiofs share into a running guest or sandbox without a prompt, and `workloads share detach` removes it.
A guest takes the [guest shares](../apps/libvirt/shares.md) its declaration marks `runtime = true`.
A sandbox takes its own `shared` directory read-write, or a `workloads.grants.sandboxShares` entry from [grants.nix](../../modules/workloads/sharing/grants.nix) read-only.

## Declare runtime shares

In `modules/hosts/<host>/workloads.nix`:

```nix
_: {
  configurations.nixos.<host>.module.workloads = {
    guests.<name>.shares.<tag> = {
      hostPath = "<directory>";
      runtime = true;
    };
    grants.sandboxShares.<tag>.hostPath = "<directory>";
  };
}
```

- Either kind turns the `workloads` app on and lands in `/etc/workloads/grants.json`.
- Any present guest starts `workload-grantd`, so a live share stays detachable after its declaration goes.
- A sandbox share tag follows the guest tag rules and is never `shared`; evaluation fails otherwise.
- `sbx` refuses a sandbox share whose directory, after links resolve, is missing, is or holds `$HOME`, or overlaps the sbx state directory.

## Attach and detach

As the owner on the host:

```sh
workloads share attach <guest> <tag>
workloads share detach <guest> <tag>
sbx share attach <name> shared
sbx share attach <name> <tag>
sbx share detach <name> <tag>
```

`workloads share attach sbx-<name> <tag>` runs `sbx share attach`, which mounts the share as well; its answer leaves out the mount fields.
A NixOS guest's runtime share has a `noauto` fstab entry, so `mount /mnt/<tag>` in the guest mounts it.
`sbx share attach` mounts the tag on `/mnt/<tag>` in the sandbox, read-only with `-o ro`, and returns `mount_command` and `unmount_command`.
`--no-mount` only attaches; a mount the guest refuses keeps the share attached with `mounted: false` and `mount_error`.

- A share stays until it is detached or the guest stops; a managed save and its restore keep it.
- A guest has a hot-plug slot for each runtime share it declares, and a sandbox for a few shares; a further attach fails with `libvirt`.
- Detach returns once the device has left the live definition; unmount a system guest's share inside the guest first.
- `sbx share detach` unmounts every guest mount of the tag first, and refuses a busy one with `share-busy` unless `--force` unmounts it lazily.
- A sandbox whose guest agent does not answer is detached anyway, with `guest_unmounted: false` and a `recovery_command`.
- `sbx info <name>` lists the shares a sandbox holds, each with its mountpoint when the guest mounted it.
- A share shows host files with their mode bits, so executables stay executable; a `cp` out strips execute, setuid, and setgid bits.
- Detach also removes a live share that the guest's declaration omits.
- A guest that keeps the device past the wait fails detach with `detach-pending`, and the share stays usable until the guest releases it or stops.
- `shared` refuses to attach past the sbx disk cap or free-space floor, and `sbx gc` then unmounts it lazily in each guest and detaches it, as `sbx share detach --force` does.
- Between those checks a guest writes without bound, since no size-capped filesystem holds `shared`.
- `workloads share` refuses Windows guests and Windows sandboxes; [guest shares](../apps/libvirt/shares.md#runtime-shares) gives their procedure.
- Every verb takes `--json`, with errors shaped as for [grants](workload-grants.md#grant-from-the-command-line).

| Code                | Cause                                   |
| ------------------- | --------------------------------------- |
| `not-declared`      | no runtime or sandbox share has the tag |
| `unsupported-guest` | the guest runs Windows                  |
| `not-running`       | the guest or sandbox is not running     |
| `not-found`         | no sandbox has the name                 |
| `disk-full`         | sandboxes pass the disk cap or floor    |
| `expired`           | the sandbox is past its TTL             |
| `already-attached`  | the share is attached                   |
| `not-attached`      | the share is not attached               |
| `saved`             | a managed save holds the share          |
| `detach-pending`    | the guest still holds the device        |
| `share-busy`        | a guest process uses the mount          |
| `path-denied`       | the sandbox share directory is refused  |
| `libvirt`           | virsh or libvirt failed                 |
| `invalid-target`    | the target does not parse               |

## How a share attaches

- A guest share goes through [workload-grantd](workload-grants.md#the-helper), which checks the guest and tag against the policy file and journals the decision under `SYSLOG_IDENTIFIER=workload-grant`.
- libvirtd admits a root client without polkit, so the helper keeps `CAP_NET_ADMIN` as its only capability.
- The helper attaches the device file the policy names and detaches the live device by its alias.
- A sandbox share needs no root: `sbx share` reads the policy file, hot-plugs into the sandbox's `qemu:///session` domain, and journals under `SYSLOG_IDENTIFIER=sbx`.
- `shared` sits in the sandbox's run directory, and no host sbx code writes into it, so a link the guest plants there leads host code nowhere.
- Session virtiofsd maps no id but the owner's, and squashes every guest uid and gid onto the owner, so the owner can delete every file a guest leaves.
- The guest sees every file as owned by a GUI base's `sbx` user, so a non-root guest user writes too.
- Every sandbox has shared memfd memory, which virtiofs needs.

## Verify

As the owner on the host:

```sh
journalctl -t workload-grant -n 20
virsh -r -c qemu:///system dumpxml <guest> | grep -A6 '<filesystem'
journalctl --user -t sbx -n 20
sbx exec <name> -- findmnt -t virtiofs
```

## Detach fails with detach-pending

Cause: the guest has not acknowledged the PCI hot-unplug, so libvirt keeps the device.

```sh
virsh -r -c qemu:///system dumpxml <guest> | grep -A6 '<filesystem'
```

Fix: unmount the share in the guest and detach again, or shut the guest down; `sbx destroy <name>` ends a sandbox's share.

## Guest I/O fails with Transport endpoint is not connected

Cause: the share left while the guest still had it mounted, as after a detach whose guest agent did not answer.

```sh
sbx exec <name> -- findmnt -t virtiofs
```

Fix: run the `recovery_command` the detach returned, which unmounts the stale mounts lazily.
