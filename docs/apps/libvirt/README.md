# libvirt

The `libvirt` app runs the system libvirtd (`qemu:///system`) with QEMU/KVM; `virt-manager` and `virt-viewer` are its clients.
`modules/workloads/vms/` turns declared workload networks and [guests](guests.md) into libvirt objects and stages installation media for them.
Guests created in virt-manager stay outside the declarations and are never touched by them.

## Access

- No user joins the `libvirtd` group.
  A read-write `qemu:///system` connection asks for admin authentication on every connect, never reusing a recent one.
- A read-only connection (`virsh -r -c qemu:///system`) needs no authentication.
- Root bypasses polkit, so the units below need no prompt.
- Plain `virsh` as the owner talks to `qemu:///session`, since no default URI is set.
  virt-manager connects to `qemu:///system` on its own.
- QEMU runs as `qemu-libvirtd`, so a file a guest opens must be readable by that user.
- SPICE and VNC consoles without a listen address use a unix socket, so opening one goes through an authenticated libvirt connection.
- Host shutdown asks each running guest to shut down and waits at most `shutdownTimeout` from `modules/apps/libvirt.nix` per guest; boot resumes none.
- Host suspend pauses running guests and hibernation saves them: [Guests across host sleep](sleep.md).

## Declare a libvirt network

A libvirt network extends a workload network from [Workload networks](../../networking/workloads.md), which owns its firewall, egress, and addressing.
Add a `libvirt` block to the declaration in `modules/hosts/<host>/workloads.nix`:

```nix
_: {
  configurations.nixos.<host>.module.workloads.networks.<name>.libvirt = {
    enable = true;
    uuid = "<uuidgen output>";
    dhcp = {
      start = <first host part>;
      end = <last host part>;
    };
  };
}
```

- The UUID is the network's identity; generate it once and never change it.
- The DHCP range is given as host parts of the network's subnet.
- `autostart` starts the network with the daemon, and `sessionAttach` admits `qemu:///session` guests to the bridge.
- A declared network turns the `libvirt` app row on.

The network uses forward mode `open`, so libvirt writes no firewall rules and only the workload tables govern its traffic.
libvirt's dnsmasq serves DHCP with the network MTU and a reservation for each declared guest interface.
On `warp` networks it forwards DNS to WARP's local resolvers only, so lookups fail while WARP is down; `none` networks get no DNS.
It never answers from the host's `/etc/hosts`, which carries Mesh names.

## How a network is applied

`workloads-vm-net-<name>.service` defines the network from XML that `virt-xml-validate` checked at build time.
The unit reruns at boot, at a switch that changes its XML, autostart flag, or reconciler, and when libvirtd restarts.

- The reconciler defines and never destroys or restarts.
  A running network keeps its old definition until it is restarted by hand, and the unit logs the command.
  DHCP reservations are the exception: they change on the running network.
- An inactive network with `autostart` is started after the define.
- Every defined network carries a workloads ownership marker in its metadata.
  The reconciler refuses to change a network that lacks it.
- The UUID finds the network.
  A name held by another UUID, or a UUID defined under another name, fails the unit.
- libvirt's stock `default` network is the one exception: inactive, unmarked, and on its stock address, it is undefined and the declared `default` takes its name.
  Any other unmarked `default` fails the unit.
- Removing a declaration leaves the network defined, running, and set to autostart.
  A defined `default` keeps libvirt from restoring its stock network.

## Staged media

`workloads.media.<name>` names a file by runtime path, so it never enters the store:

```nix
workloads.media.<name> = {
  source = "/path/to/installer.iso";
  sha256 = "<hex digest>";
};
```

`workloads-vm-media.service` copies each source to `/var/lib/workloads/media/<name>` as a root-owned file that QEMU can read.
It reads the source with the owner's permissions and accepts only a regular file, so a symlink to a root-only file or a device stages nothing.
It copies again only when the size or modification time changes, checks the optional hash on every run, and deletes staged files without a declaration.
A partial copy never stays behind, and a hash mismatch publishes nothing.
libvirt hands an attached image to `qemu-libvirtd` and never gives it back; the next run of the unit, at boot or a switch, resets owner and mode.
Names are lowercase letters, digits, `.`, `_`, and `-`, starting with a letter or digit.
The unit requires the mount that holds each source, so an absent volume fails it instead of staging nothing.

## Remove a network

Removing a declaration, or switching back to a generation without it, leaves libvirt's network running with its bridge and dnsmasq.
The workload table drops everything from a `vn-*` interface that no declaration names, so the bridge stays fenced and inert, and forwarding goes off with the last network.
Shut down its guests, then remove the network by hand:

```sh
virsh -c qemu:///system net-destroy <name>
virsh -c qemu:///system net-undefine <name>
```

A generation without the workload module has no such fence, so destroy the network before switching to one.
Keep `default` defined when only its declaration changes, since an undefined `default` lets libvirt restore its stock network at the next daemon start.

## Verify

As the owner on the host:

```sh
systemctl status libvirtd.socket workloads-vm-media.service 'workloads-vm-net-*'
virsh -r -c qemu:///system net-list --all
virsh -r -c qemu:///system net-dumpxml <name>
ip -br addr show vn-<name>
```

## workloads-vm-net-name fails on an unmarked network

Cause: a network with the declared name or UUID was created by hand or by another tool, so the reconciler will not take it over.

```sh
journalctl -u workloads-vm-net-<name>.service -b
virsh -r -c qemu:///system net-dumpxml <name> --inactive
```

Fix: after moving any guests off it, remove the conflicting network, then restart the unit:

```sh
virsh -c qemu:///system net-destroy <name>
virsh -c qemu:///system net-undefine <name>
sudo systemctl restart workloads-vm-net-<name>.service
```

## A network change has no effect

Cause: the network was running at the switch, so its new definition waits for a restart.

```sh
journalctl -u workloads-vm-net-<name>.service -b | grep 'older definition'
```

Fix: shut down the guests on the network, then restart it; running guests would lose their link.

```sh
virsh -c qemu:///system net-destroy <name> && virsh -c qemu:///system net-start <name>
```

## workloads-vm-media fails at boot

Cause: a declared source sits on a volume that was not mounted, such as an unopened `/data`.

```sh
journalctl -u workloads-vm-media.service -b
```

Fix: mount the volume, then `sudo systemctl restart workloads-vm-media.service`.
