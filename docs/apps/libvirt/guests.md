# Declared libvirt guests

`workloads.guests.<name>` declares a long-lived guest on `qemu:///system`; `modules/workloads/vms/` renders its domain XML and defines it.
The options and their defaults are documented in `modules/workloads/vms/options.nix`.
Guests created in virt-manager stay outside the declarations, as described in [libvirt](README.md).

## Declare a guest

Declare the guest in `modules/hosts/<host>/workloads.nix`, on a network with a libvirt block:

```nix
_: {
  configurations.nixos.<host>.module.workloads.guests.<name> = {
    uuid = "<uuidgen output>";
    kind = "nixos";
    trust = "trusted";
    memory = <MiB>;
    vcpus = <count>;
    disks.root.size = <GiB>;
    interfaces.lan = {
      network = "<network>";
      hostOffset = <host part below the DHCP range>;
    };
  };
}
```

- The UUID is the guest's identity; generate it once and never change it.
- Disks, NVRAM, and TPM state live in `/var/lib/workloads/guests/<uuid>/`; MAC addresses derive from the UUID and the interface name.
- Each interface gets a DHCP reservation at its host offset, which lies outside the network's DHCP range.
- `kind = "windows"` requires Secure Boot with Microsoft keys enrolled and a TPM.
  [Windows guests](windows.md) covers the unattended install, provisioning, and golden copies of any guest.
- `install.media` attaches staged media as CD-ROMs that boot after the disks, so an empty disk falls through to the installer.
  `install.images` attaches `workloads.images` entries as CD-ROMs that never boot.
- A declared guest turns the `libvirt` app row on.

## Trust classes

| Setting                   | trusted       | untrusted      |
| ------------------------- | ------------- | -------------- |
| SPICE agent channel       | yes           | with clipboard |
| Clipboard                 | on by default | opt-in         |
| File transfer             | on by default | off, forced    |
| Display resizing by agent | yes           | with clipboard |
| [Shares](shares.md)       | declared      | none           |

An untrusted guest gets a clipboard, and with it the SPICE agent channel, only with `clipboard = true` and `allowUntrustedClipboard = true`.
A SPICE console listens on a unix socket only, so opening it goes through a libvirt connection authorized by polkit.
`display = "headless"` drops the SPICE console and leaves the serial console; the guest agent channel follows `guestAgent` either way.

## How a guest is applied

`workloads-vm-guest-<name>.service` defines the guest from XML that `virt-xml-validate` checked at build time.
It reruns at boot, at a switch that changes the guest's definition, and when libvirtd restarts.

- The reconciler defines and never destroys, restarts, or shuts down a guest.
  A running guest keeps its old definition until its next cold boot, and the unit logs that a change is pending.
  A reboot inside the guest keeps the old definition; a shutdown and a start apply the new one.
- An `autostart` guest starts with libvirtd; the unit also starts it once, right after its first define.
- Every defined guest carries the workloads ownership marker, and a guest without it is never changed.
- The UUID finds the guest.
  A guest renamed in Nix is renamed in libvirt while shut off; while it runs, the unit fails until it is shut down.
- A declared name held by another UUID, or a declared UUID held by an unmarked domain, fails the unit.

A guest added to a running network gets its reservation live; the network keeps running.

## Disks and NVRAM

- A disk is created only while the guest directory holds no NVRAM: empty, or copied from a qcow2 `workloads.images` seed.
  A disk file already present at that path is kept, so a guest declared again after `ensure = "absent"` keeps its data.
- NVRAM is copied from the firmware's variable template as the last step of the first define, so an interrupted first define resumes on the next run.
- Once NVRAM exists, a missing disk fails the unit instead of being recreated, even when the domain itself was undefined.
  A disk added to an existing guest is therefore created by hand with `qemu-img create -f qcow2` before the switch.
- Missing NVRAM next to TPM state fails the unit; without TPM state it is copied from the template again.
- TPM state is persistent, so libvirt keeps it when a domain is undefined, also by hand or from virt-manager.
- A disk larger than its declared size fails the unit; disks never shrink.
- A changed firmware option leaves the existing NVRAM in place, so new Secure Boot keys need an NVRAM reset at the next start.

A seed names an image by the out-link `nix build` leaves under `/var/lib/workloads/images`, so no image enters the system closure.
While the out-link is stale or missing, a guest that libvirt has not defined and whose disk does not exist yet stays undefined, and its unit logs a warning.
The same holds for `install.images` out-links and for `install.media` that are not staged yet, while the guest has no NVRAM.
A defined guest in that state fails the unit; neither seeds an old image.
[NixOS guests](nixos-guests.md) covers building such an image from a guest configuration.

## Grow a disk

Precondition: the guest is shut off.

1. Grow the image as root:

   ```sh
   qemu-img resize /var/lib/workloads/guests/<uuid>/<disk>.qcow2 <GiB>G
   ```

2. Set the new `disks.<disk>.size` and switch.

3. Grow the partition and file system inside the guest.

Verification: `journalctl -u workloads-vm-guest-<name>.service -b` shows no size message.

## Remove a guest

1. Shut the guest down, and delete its snapshots and any managed save image.
2. Set `ensure = "absent"` on the declaration and switch.

The unit undefines the guest and keeps its directory; deleting the files is a manual step.
A guest whose declaration is dropped instead stays defined, and `workloads-vm-orphans.service` warns about it and about every owned network that nothing declares.

## Verify

As the owner on the host:

```sh
systemctl status 'workloads-vm-guest-*' workloads-vm-orphans.service
virsh -r -c qemu:///system list --all
virsh -r -c qemu:///system dumpxml <name> --inactive
journalctl -u workloads-vm-orphans.service -b
```

## workloads-vm-guest-name fails after a rename

Cause: the guest still runs under its old name, and libvirt renames only shut-off domains.

```sh
journalctl -u workloads-vm-guest-<name>.service -b
```

Fix: shut the guest down, then `sudo systemctl restart workloads-vm-guest-<name>.service`.

## workloads-vm-guest-name fails on a missing disk or NVRAM

Cause: a file in the guest directory was moved or deleted after the first define.

```sh
ls -l /var/lib/workloads/guests/<uuid>/
```

Fix: restore the file from a backup, then restart the unit.

## A guest change has no effect

Cause: the guest was running at the switch, so the new definition waits for its next cold boot.

```sh
journalctl -u workloads-vm-guest-<name>.service -b | grep 'older definition'
```

Fix: shut the guest down from inside or with `virsh -c qemu:///system shutdown <name>`, then start it.
