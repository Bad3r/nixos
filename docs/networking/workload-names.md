# Workload names

[names.nix](../../modules/workloads/sharing/names.nix) gives declared workloads names on the host and inside [workload networks](workloads.md).
`workloads.names.<name>` holds each object's address, kind, and network.
Every present guest with an interface adds itself as kind `guest`, and every [declared service](workload-services.md) on a Podman network as kind `service`.
Service names resolve on the host, and inside a network only where a guest on it links to the service.
Names match `[a-z0-9][a-z0-9-]*`, and `host` is reserved for the gateway.

## Host names

The host resolves every `workloads.names` entry as `<name>` and `<name>.vm` through `networking.hosts`.
A guest on several networks resolves on the host to the address of its first interface in name order.

```sh
getent hosts <name>.vm
ssh <user>@<name>.vm
```

## Names inside a network

The gateway's resolver answers `host.vm` with the gateway address.
A libvirt network's `resolve` list adds guest and linked service names, each as `<name>` and `<name>.vm`:

```nix
_: {
  configurations.nixos.<host>.module.workloads.networks.<network>.resolve = [ "<name>" ];
}
```

- A `resolve` entry that is not a `workloads.names` key fails evaluation.
- A service name fails evaluation unless a guest on the network has a `service:<name>` [workload link](workload-links.md), since the forward chain drops traffic between bridges otherwise.
- Inside a Podman network, containers resolve each other through aardvark-dns's own names; `<name>` and `<name>.vm` from `workloads.names` do not resolve there, and a `resolve` list fails evaluation.
- A guest with an interface on the network resolves to that interface's address there.
- dnsmasq also answers bare names from DHCP reservations and leases, so guests should look up the `.vm` form.
- The resolver answers unknown `.vm` names with NXDOMAIN and never forwards them.
- A `none` network runs no resolver, so its guests resolve no names, `host.vm` included.
- A name resolves; reaching it still takes a port the firewall opens.

A switch adds and drops the records of a running network in place, so attached guests keep their links.
Other changes to a running network's resolver wait for a network restart, which the `workloads-vm-net-<network>` journal names.

## List names

The `workloads` app turns on while any name is declared.
`workloads names` lists declared names, the records each network's resolver serves, and live sandboxes:

```sh
workloads names
workloads names --json
```

Sandboxes come from `sbx list --json`.
Without sbx on PATH, the command says so on stderr and reports `"sandboxes": null`; an sbx failure fails the command.
The declared side comes from `/etc/workloads/names.json`, which ships with the app and lists nothing while no name is declared.

## Verify

Run as the owner on the host, with a gateway address from `workloads names`:

```sh
getent hosts <name>.vm
dig +short @<gateway> host.vm
dig +short @<gateway> <name>.vm
virsh -r -c qemu:///system net-dumpxml <network> | grep -A2 '<host ip'
```

## A guest cannot resolve host.vm

Cause: the network's egress is `none`, or the guest asks a resolver other than its gateway.

```sh
dig +short @<gateway> host.vm
```

Fix: an answer here means the guest's resolver is wrong; point it at the gateway, which DHCP hands out.
No answer on a `warp` network means the network is inactive; `sudo systemctl restart workloads-vm-net-<network>.service` starts an autostart network.

## workloads names lists no sandboxes

Cause: sbx is not installed, which the stderr line states, or no sandbox runs.

```sh
command -v sbx && sbx list
```

Fix: turn on the `sbx` row in the host's `apps-enable.nix`; [sbx](../apps/sbx/README.md) covers the sandboxes themselves.
