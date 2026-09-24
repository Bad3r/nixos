# WinApps Windows guest

`modules/hosts/common/windows-guest.nix` declares a Windows guest on libvirt `qemu:///system` through NixVirt.
The declaration covers two NAT networks, a storage pool, the disk volume, and the domain `RDPWindows`.
A host opts in with `host.virtualization.windowsGuest.enable`.

## Pages

- [provisioning.md](provisioning.md): first switch, install media, Windows installation, guest tools, isolation check, media detach.
- [storage.md](storage.md): baseline copy, restore, and disk growth.

## Lifecycle

- The guest starts on demand; NixVirt defines it and never starts or stops it.
- Host shutdown shuts the guest down through `libvirt-guests`.
  The host powers the guest off when the libvirt shutdown timeout passes, so Windows updates run outside host shutdowns.
- A definition change applies at the next guest start after a full shut down.
  A restart from inside Windows keeps the running definition.
- The guest clock stops while the host sleeps, so a resume hook sets it from the host through the guest agent.

## Rules that prevent data loss

- Never set `present = false` on the volume.
  It is the one NixVirt setting that deletes the disk image.
- The domain UUID, the NVRAM path, the pool path, and the volume name are identity.
  libvirt keys the TPM state, the UEFI variable store, and the disk on them, so a change strands guest state.
- The `winapps` network UUID is identity as well.
  NixVirt destroys every domain on a network it replaces, so a change powers a running guest off once and keeps its disk, NVRAM, and TPM state.
- NixVirt treats its lists as exhaustive.
  At every boot and every switch it powers off and undefines each domain, network, and pool that the module does not declare.
  Their disks, NVRAM files, and TPM state stay on disk.
- Declare a guest in Nix before relying on it; a guest made by hand in virt-manager lasts until the next switch.
- An edit made in virt-manager to a declared object is overwritten at the next switch.
- Never run `virsh undefine` with `--nvram` or `--tpm`, or `virsh vol-delete`, against the guest.
- Copy guest state only while the guest is shut off.
  Keep the disk, the NVRAM file, the TPM state directory, and the domain XML together.

## State

libvirt reports where the guest state lives:

```sh
virsh --connect qemu:///system vol-path --pool winapps RDPWindows.qcow2
virsh --connect qemu:///system dumpxml RDPWindows --xpath '//os/nvram'
virsh --connect qemu:///system domuuid RDPWindows
```

The TPM state sits in `/var/lib/libvirt/swtpm/` under the domain UUID.

## Isolation

The guest network is a NAT network on a subnet outside the sources that `modules/hosts/common/firewall.nix` trusts.
The host refuses new connections from the guest except DHCP and DNS, so the guest reaches the internet and no host service.
Replies to connections the host opens, such as RDP, still pass.

Sources: [NixVirt](https://github.com/AshleyYakeley/NixVirt), [libvirt domain XML](https://libvirt.org/formatdomain.html), [WinApps libvirt guide](https://github.com/winapps-org/winapps/blob/main/docs/libvirt.md).
