# Workload services

`workloads.services.<name>` runs one container on rootful Podman, attached to a [workload network](workloads.md).
[units.nix](../../modules/workloads/services/units.nix) renders it as `virtualisation.oci-containers.containers.svc-<name>`, whose unit is `podman-svc-<name>.service`.
The `inet workload` table fences the container like any other guest: it reaches the gateway for DNS and ping, its egress follows the network's mode, and nothing reaches the LAN, Mesh, or another network.

## Declare a service

1. Register the network as in [Declare a network](workloads.md#declare-a-network) and set `podman.enable` on it.
2. Declare the service in `modules/hosts/<host>/workloads.nix`:

```nix
_: {
  configurations.nixos.<host>.module.workloads = {
    networks.<network>.podman.enable = true;
    services.<name> = {
      image = "<registry>/<image>:<tag>";
      network = "<network>";
      address = <host part>;
      ports = [ { host = <port>; container = <port>; } ];
      volumes = [ "/var/lib/<name>:/data:idmap" ];
      autostart = true;
    };
  };
}
```

- Service names follow the [workload name](workload-names.md) rule: `[a-z0-9][a-z0-9-]*`, never `host`.
- `address` fixes the container's address inside the network's subnet; two services on one network need different values.
- `ports` publish on the host's `127.0.0.1` only, IPv4 without `::1`; the host reaches the container's own address directly as well.
- A published port shadows any host listener on `127.0.0.1` with the same port, without an error.
- `imageFile` loads a Nix-built archive, such as a `dockerTools.buildImage` result, before each start.
- Without `autostart`, the container runs only after `sudo systemctl start podman-svc-<name>.service`.
- Settings without an option, such as `cmd`, `environment`, or `environmentFiles`, go on `virtualisation.oci-containers.containers.svc-<name>` in the same host module.

A declared network or service turns the podman app row on.
The rootful API socket stays off, so the owner reaches these containers only through `sudo podman`.

## User namespaces

Every service runs with `--userns=auto`, so root in the container is an unprivileged id on the host.
Podman draws the ids from the subordinate ranges of the `containers` system user, a block clear of systemd's container ranges and the owner's own range.
A host directory mounted read-write needs the `:idmap` volume option, which maps the container's ids back to the directory's owners without a chown.
`:U` works too, but chowns the whole tree again whenever a start draws a different id range, since `--userns=auto` allocates one per container.

## Shares

`shares.<tag>` mounts a host directory through an idmapped mount that maps the share's `owner` to container root:

```nix
workloads.services.<name>.shares.<tag> = {
  hostPath = "<directory>";
  readOnly = true;
};
```

- Container root reads and writes as the owner and its primary group, so the owner edits the results without `sudo`.
- Other container users create nothing in the share, and files of other host accounts show as the overflow id.
- The directory must exist when the container starts; only a service's [drop](workload-drops.md) is created for it.
- The share assertion in `modules/workloads/services/units.nix` refuses a root owner, a root primary group, and an owner without a fixed uid and gid.

## Networks in Podman

`workloads-podman-net-<network>.service` creates the Podman network with the bridge, subnet, gateway, and MTU of the registry entry.
The network carries a label holding a hash of that spec, which also marks it as owned:

- an owned network whose hash matches is kept;
- an owned network whose hash differs is removed and created again, and a switch stops its containers first;
- a network of the same name without the label stops the unit with an error and is left alone;
- a `vn-<network>` interface that no labelled network owns, such as a libvirt bridge, also stops the unit.

Every container start runs the same check, so a network removed by hand returns with its next start.
To move a network from libvirt to Podman, undefine the libvirt network first with `sudo virsh net-destroy <network>` and `sudo virsh net-undefine <network>`.
A network removed from the configuration stays defined in Podman until `sudo podman network rm <network>`.
The unit requires `nftables.service` and `workload-egress.service` and runs after both, so a container never runs on a bridge the workload table and egress rules do not fence.

## Firewall ownership

While a Podman network is declared, `/etc/containers/containers.conf` sets netavark's `firewall_driver` to `none`, so netavark writes no table and `inet workload` alone filters and masquerades the bridges.
`/etc/containers/containers.rootless.conf` restores `nftables` for rootless Podman, whose networks live inside its own namespace.
Rootful containers outside `workloads.services`, including any on `podman0`, therefore get no port forwarding or masquerade from netavark.

Published ports are DNAT rules in the `services-output` chain of `inet workload`, from `127.0.0.1` to the container's address.
A masquerade rule rewrites the loopback source to the gateway, and netavark sets `route_localnet` on the bridge so the rewritten packet can leave through it.
`route_localnet` would also let a container address the host's loopback, which the input chain's final drop rejects.

## DNS

On a `warp` network, aardvark-dns answers on the gateway, resolves the names of containers on the same network, and forwards the rest to WARP's local resolvers only, so lookups fail while WARP is down.
The gateway is the container's only nameserver, so Podman appends no public fallback servers.
A `none` network has DNS turned off, and Podman writes no `/etc/resolv.conf` into its containers; an image's own file stays unchanged.
Containers start from an empty hosts file instead of the host's `/etc/hosts`, which carries Mesh names.
Names on the host and in linked guests' networks: [Workload names](workload-names.md).

## Verify

Run as the owner on the host:

```sh
sudo podman network inspect <network>
sudo podman inspect --format '{{.NetworkSettings.Networks.<network>.IPAddress}}' svc-<name>
sudo podman exec svc-<name> cat /etc/resolv.conf
sudo nft list chain inet workload services-output
sudo nft list tables | grep netavark
curl -sI http://127.0.0.1:<port>/
```

The `grep` prints nothing while netavark's firewall is off.

The `workloads-services` flake check boots a VM that declares one network and one service and checks the bridge, the container's address, DNS, the published port, the id mappings of volumes and shares, and the network unit's ownership handling.
Build it from the repository root on a host with KVM:

```sh
nix build "path:.#checks.x86_64-linux.workloads-services"
```

## Network unit fails with a missing label

Cause: a Podman network with the declared name exists and was not created by the unit.

```sh
sudo podman network inspect --format '{{.Labels}}' <network>
```

Fix: remove or rename that network with `sudo podman network rm <network>`, then `sudo systemctl start podman-svc-<name>.service`.

## Network unit fails to remove a network

Cause: the spec changed while a container outside the declared services is still attached.

```sh
sudo podman ps --all --filter network=<network>
```

Fix: stop and remove that container, then start the service again.

Upstream reference: <https://docs.podman.io/en/latest/markdown/podman-network-create.1.html>
