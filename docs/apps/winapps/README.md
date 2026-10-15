# WinApps Windows guest

`modules/hosts/common/windows-guest.nix` declares a Windows guest on libvirt `qemu:///system` through NixVirt.
The declaration covers the shared NAT network, a storage pool, the disk volume, and the domain `RDPWindows`.
A host opts in with `host.virtualization.windowsGuest.enable`.

## Pages

- [provisioning.md](provisioning.md): first switch, install media, Windows installation, guest tools, shared-network check, media detach.
- [storage.md](storage.md): baseline copy, restore, and disk growth.
- [shared-folder.md](shared-folder.md): persistent file sharing, Windows service setup, and host ownership checks.

## Lifecycle

- The guest starts on demand; NixVirt defines it and keeps the run state it finds.
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
- The `default` network UUID is identity too; NixVirt powers off every guest on a network it replaces.
- Shut down every guest on `default` before a switch that changes the network definition.
  Otherwise the network restart powers each running guest off without a shutdown, and NixVirt then boots `RDPWindows` again.
- NixVirt treats its lists as exhaustive.
  At every boot and every switch it powers off and undefines each domain, network, and pool that the module does not declare.
  Their disks, NVRAM files, and TPM state stay on disk.
- Declare a guest in Nix before relying on it; one made by hand in virt-manager lasts until the next boot or switch.
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

## Shared VM network

The `default` libvirt NAT network uses `10.11.11.0/24` on host bridge `virbr0`.
The host uses `10.11.11.1`, `RDPWindows` reserves `10.11.11.2`, and DHCP leases `.3` through `.254` to other VMs.

Guests on the bridge reach one another directly over TCP ports `8000` through `9999`.
The host accepts that range on `virbr0` only from `10.11.11.0/24`.
The QEMU guest-agent reconciler installs the matching inbound rule in `RDPWindows`.
Another Windows VM on the bridge that serves the range needs the same rule:

```powershell
New-NetFirewallRule -Name 'NixOS-Guest-Services-TCP-8000-9999' -DisplayName 'NixOS guest services TCP 8000-9999' -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP -LocalPort '8000-9999' -RemoteAddress '10.11.11.0/24'
```

The host still refuses other new connections from the bridge, including SSH.
`modules/hosts/common/firewall.nix` leaves `10.11.0.0/16` out of the local source ranges it trusts.
DHCP, DNS, outbound NAT, and replies to host-initiated connections remain available.

Sources: [NixVirt](https://github.com/AshleyYakeley/NixVirt), [libvirt domain XML](https://libvirt.org/formatdomain.html), [WinApps libvirt guide](https://github.com/winapps-org/winapps/blob/main/docs/libvirt.md).
