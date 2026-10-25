# Workload file drops

A drop is a host directory for handing files to one declared workload, `/var/lib/workloads/shares/<name>`, linked at `~/workloads/<name>`.
`modules/workloads/sharing/drops.nix` adds it as the `drop` entry of the workload's `shares`, creates its directory, and links it.

## Who gets a drop

| Workload        | Drop    | Inside                        |
| --------------- | ------- | ----------------------------- |
| trusted guest   | default | `/mnt/drop` or a drive letter |
| untrusted guest | none    | none                          |
| service         | opt-in  | `/mnt/drop`                   |

- A trusted guest gets the drop as a [virtiofs share](../apps/libvirt/shares.md).
  `workloads-guest-base` mounts it at `/mnt/drop` in a NixOS guest, and a Windows guest mounts it on a drive letter.
- `shares.drop.enable = false` opts a trusted guest out.
- Untrusted guests get no shares; a sandbox exchanges files through [sbx copies](../apps/sbx/README.md#copies).
- A [workload service](workload-services.md#shares) opts in with `shares.drop.enable = true`.
- The directory path is fixed; any other directory goes into a share with its own tag.

Declarations in `modules/hosts/<host>/workloads.nix`:

```nix
_: {
  configurations.nixos.<host>.module.workloads = {
    guests.<guest>.shares.drop.enable = false;
    services.<service>.shares.drop.enable = true;
  };
}
```

## Directory and link

- `systemd-tmpfiles` creates the directory for the share's `owner` and primary group, closed to every other account.
- Home Manager links `~/workloads/<name>` in the owner's home to it and removes the link once the drop is gone.
- Guest and container writes land owned by the owner, so the owner edits and deletes them without `sudo`.
- Removing a drop, its guest, or its service keeps the directory and its files.

Delete a directory nothing declares any more, as the owner:

```sh
sudo rm -r /var/lib/workloads/shares/<name>
```

## When a drop applies

- A switch creates the directory and the link.
- A guest gets the share as any [new share](../apps/libvirt/shares.md#declare-a-share) does: at its next cold boot, after a redeploy for a NixOS guest's fstab.
- A service gets it when the switch restarts its container.

## Verify

As the owner on the host:

```sh
ls -ld ~/workloads/<name>/ /var/lib/workloads/shares/<name>
virsh -r -c qemu:///system dumpxml <guest> | grep -A3 "<target dir='drop'"
sudo podman exec svc-<service> ls -ln /mnt/drop
```

In a NixOS guest:

```sh
findmnt /mnt/drop
```

In a Windows guest, the drive letter is the `drop` entry of the guest's `windows.virtiofs.driveLetters`.

## The link in the home directory is missing

Cause: Home Manager activation for the active generation failed or has not run.

```sh
systemctl status home-manager-$USER.service
journalctl -u home-manager-$USER.service -b
```

Fix: resolve the logged conflict, then `sudo systemctl restart home-manager-$USER.service`.

## A guest drop is empty inside the guest

Cause: the running guest predates its drop share, or the NixOS guest runs a generation without the fstab entry.

```sh
virsh -r -c qemu:///system dumpxml <guest> | grep -c "<target dir='drop'"
```

Fix: redeploy a NixOS guest, then shut the guest down and start it again.
