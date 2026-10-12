# WinApps Windows guest

`modules/hosts/common/windows-guest.nix` declares a Windows guest on libvirt `qemu:///system` through NixVirt.
The declaration covers the shared NAT network, a storage pool, the disk volume, and the domain `RDPWindows`.
A host opts in with `host.virtualization.windowsGuest.enable`.

`modules/apps/winapps.nix` installs the WinApps launcher that presents the guest's programs over FreeRDP RemoteApp.
`modules/hm-apps/winapps.nix` writes the launcher configuration and the `Outlook Classic` menu entry.

## Pages

- [provisioning.md](provisioning.md): first switch, install media, Windows installation, guest tools, shared-network check, media detach.
- [remoteapp-setup.md](remoteapp-setup.md): the guest-side registry import, the firewall scope, and the Outlook path check.
- [storage.md](storage.md): baseline copy, restore, and disk growth.
- [shared-folder.md](shared-folder.md): persistent file sharing, Windows service setup, and host ownership checks.
- [operations.md](operations.md): the RDP password, certificate trust, launching Outlook Classic, the full desktop, the launcher boundary, shutdown, updates, and discontinuing.
- [troubleshooting.md](troubleshooting.md): launcher and RemoteApp failures, each with a diagnostic and a fix.

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
- The `default` network UUID remains stable when its address changes.
- The first switch to the shared network removes the old `winapps` network.
  Gracefully shut down `RDPWindows` first; otherwise NixVirt powers it off while removing the network.
  The disk, NVRAM, and TPM state stay on disk.
- Stop every guest attached to `default` before changing its subnet.
  NixVirt restarts the bridge when its network definition changes.
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

## Shared VM network

The `default` libvirt NAT network uses `10.11.11.0/24` on host bridge `virbr0`.
The host uses `10.11.11.1`, `RDPWindows` reserves `10.11.11.2`, and DHCP leases `.3` through `.254` to other VMs.

Attach additional VMs to `default` in virt-manager.
Guests on the bridge can reach one another directly over TCP ports `8000` through `9999`.
The host accepts that range on `virbr0` only from `10.11.11.0/24`.
The QEMU guest-agent reconciler installs the matching inbound rule in `RDPWindows`.
Configure the same guest firewall rule on each additional VM that needs to accept connections:

```powershell
New-NetFirewallRule -Name 'NixOS-Guest-Services-TCP-8000-9999' -DisplayName 'NixOS guest services TCP 8000-9999' -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP -LocalPort '8000-9999' -RemoteAddress '10.11.11.0/24'
```

The host still refuses other new connections from the bridge, including SSH.
The range `10.11.0.0/16` is excluded from the trusted local source CIDRs used for SSH, Samba, and the qBittorrent UI.
DHCP, DNS, outbound NAT, and replies to host-initiated connections remain available.

Sources: [NixVirt](https://github.com/AshleyYakeley/NixVirt), [libvirt domain XML](https://libvirt.org/formatdomain.html), [WinApps libvirt guide](https://github.com/winapps-org/winapps/blob/main/docs/libvirt.md).
