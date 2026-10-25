# sbx networks

A sandbox's network is set at `create` and only ever narrows: `sbx net cut` takes an `egress` sandbox offline for the rest of its life.

## Networks

- `--net none`, the default, gives the sandbox no network interface.
- `--net egress` adds one virtio NIC on `vn-sbx`, the bridge of the `sbx` [workload network](../../networking/workloads.md) in `modules/hosts/<host>/workloads.nix`, which sets its egress, isolation, and lease binding.
- Guests run the NIC at the network's `mtu`: Nix bases take it from the DHCP server, cloud bases from their seed.
- The network's resolver ignores the hostnames sandboxes send, so a sandbox cannot look up its peers.
- `create` waits for the guest's DHCP lease and prints its address.
  `list` and `info` read it from the lease file the host's DHCP server keeps for the bridge, not from the guest agent.
- The address is the sandbox's current lease, which the network keeps short.
- Session libvirt joins the bridge through the setuid `qemu-bridge-helper` wrapper.

## Cut the network

`sbx net cut <name>` lets a sandbox provision with egress, then continue offline:

```sh
sbx create debian-13 --name probe --net egress --ttl 2h
sbx exec probe -- apt-get install -y <package>
sbx net cut probe
sbx exec probe -- <command>
```

- It sets the NIC's link down, hot-unplugs the NIC, revokes the [workload grants](../../networking/workload-grants.md) keyed on the sandbox's address, and records `net: none` with a `net_cut` time.
- The result's `unplugged: false` means the guest kept the NIC past the wait; its link stays down.
- Whatever the sandbox fetched, or anything planted in it, while it had egress stays in the sandbox.
- `list` and `info` then show `net: none`, the `net_cut` time, and no address.
- A second cut, a sandbox without egress, and a Windows sandbox refuse with `invalid-argument`.
- A revoke the grant helper refuses fails the call with `grants`, after the sandbox is already offline.
