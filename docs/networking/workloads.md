# Workload networks

`workloads.networks.<name>` declares a bridge network for VMs and containers.
`modules/workloads/networks.nix` renders its firewall tables, IPv4 forwarding, and egress routing; the runtime that uses the network creates the bridge `vn-<name>` and serves DHCP on it.
Containers on rootful Podman join a network through [workload services](workload-services.md).
A network is isolated by default: guests reach the gateway for DHCP and ping, and for DNS on `warp` networks, and nothing else on the host, the LAN, Mesh, or another network.

## Table ownership

| Table                    | Owner           | Role                                   |
| ------------------------ | --------------- | -------------------------------------- |
| `inet nixos-fw`          | NixOS firewall  | opens DHCP, DNS, host ports per bridge |
| `inet workload`          | workload module | anti-spoof, input filter, forward, NAT |
| `bridge workload-peers`  | workload module | drops guest-to-guest on one bridge     |
| `bridge workload-leases` | libvirt engine  | binds guests to their DHCP leases      |
| `inet cloudflare-warp`   | warp-svc        | admits the workload block on its own   |

The `inet workload` prerouting chain drops packets from a bridge whose source lies outside its subnet before conntrack sees them, so a guest cannot inject into another network's flows.
The input chain runs one priority ahead of `nixos-fw`.
A drop in any base chain is final, so new traffic from a bridge never reaches the ports `nixos-fw` opens on every interface, and the pre-filter narrows the per-bridge opens to the gateway address.
The forward chain drops all forwarding that neither enters nor leaves a `vn-*` bridge, so turning forwarding on never makes the host a router between the LAN, Mesh, and WARP.
Once any network is declared, forwarding through other interfaces, such as rootful Podman's `podman0`, is dropped as well.
The module sets `net.ipv4.conf.all.forwarding` to 1 while at least one network is declared and to 0 otherwise, so a switch that drops the last network turns forwarding off.
It never loads `br_netfilter`; the rules behave the same with and without it.
The prerouting chain also drops everything from a `vn-*` interface that no network declares.
The table stays loaded with no network declared, so a bridge a runtime keeps after its declaration is dropped stays fenced.

## Declare a network

1. Give the network an id in `workloadNetworkIds` in `modules/hosts/<host>/policy.nix`.
   The id selects the subnet and the routing preferences; ids must differ, since two networks with one id share a subnet.
2. Declare it in `modules/hosts/<host>/workloads.nix`:

```nix
_: {
  configurations.nixos.<host>.module.workloads.networks.<name> = {
    egress = "warp";
    hostPorts.tcp = [ <port> ];
    lanAccess = false;
    isolatePeers = true;
  };
}
```

- `hostPorts` opens host ports to guests at the gateway address only.
- `lanAccess` lets guests open connections to the local network, under either egress mode.
- `isolatePeers` drops traffic between guests on the same bridge, whether bridged or routed through the gateway; the host and egress keep working.

`bridge`, `subnet`, `gateway`, and `mtu` are read-only and derived from the name, the id, and the egress mode; runtime modules read them.
The bridge name must fit the kernel's interface name limit, which the option type enforces.

## Lease binding

`isolatePeers` drops frames between guest ports only, so a guest could still claim another guest's address toward the host, through ARP or as an IP source.
A libvirt network with `libvirt.bindLeases` closes that gap in `bridge workload-leases`.

- Each guest port sends from the first MAC it uses, and no other port may use that MAC; a pin lapses after an hour of silence.
- That MAC sends IPv4 and ARP only from an address its DHCP server leased to it, until the lease expires.
- DHCP to the gateway and ARP probes pass, every other frame type is dropped, and no libvirt bridge learns an address from link-local frames.
- DHCP messages may still name any client MAC, so a guest can use up the pool or release a lease whose MAC it guesses, but it cannot send from another guest's address.

`workload-leases.service` watches libvirt's lease file and refills the leased pairs on every change, after each ruleset reload, and every 30 seconds.
A guest whose lease expired loses traffic until it renews.

## Egress modes

- `warp`: traffic leaves through the WARP tunnel, masqueraded to the host's Mesh address.
  With the tunnel gone the route is unreachable, so the network fails closed instead of falling back to the uplink.
  Guests resolve names through the gateway.
- `none`: the route is unreachable and the gateway answers no DNS, so the host resolver is no exfiltration channel.

The main table answers only the LAN destinations of a `lanAccess` network, so no route there, default or not, carries guest traffic to the uplink.

`workload-egress.service` installs one `ip rule iif vn-<name>` set per network in a preference band above WARP's own rule.
It replaces the band in one `ip -batch` call and never touches WARP's rule.
It runs at boot before `network-pre.target`, each time the WARP tunnel device appears, and on every switch.
It has no stop action, so the rules outlive the unit and stay in place while the bridge or the tunnel is absent.

## Verify

Run as the owner on the host:

```sh
sudo nft list table inet workload
sudo nft list table bridge workload-peers
sudo nft list chain inet nixos-fw input-allow | grep vn-
ip rule | grep vn-
sysctl net.ipv4.conf.all.forwarding
systemctl status workload-egress.service
```

Check the route a guest's traffic takes, with a guest address on the bridge:

```sh
ip route get 1.1.1.1 from <guest address> iif vn-<name>
```

A `warp` network answers `dev CloudflareWARP` while WARP is connected and `Network is unreachable` while it is not; a `none` network is always unreachable.

## Guest gets no address

Cause: the bridge does not exist, the runtime serves no DHCP on it, or the generation that declares the network is not active.

```sh
ip link show vn-<name>
sudo nft list chain inet nixos-fw input-allow | grep vn-<name>
```

Fix: start the runtime that owns the network, or switch to the generation that declares it.

## Guest has no internet while WARP is down

Cause: `warp` egress fails closed by design.

```sh
warp-cli --accept-tos status
```

Fix: reconnect WARP with `warp-cli --accept-tos connect`.

## workload-egress shows inactive

Cause: the unit is a oneshot without `RemainAfterExit`, so `inactive (dead)` after a successful run is its normal state.

```sh
systemctl show -p Result workload-egress.service
ip rule | grep vn-
```

Fix: none when the result is `success` and the rules are listed; otherwise read `journalctl -u workload-egress.service` and run `sudo systemctl start workload-egress.service`.

## Rules remain after removing every network

Cause: the unit has no stop action, so the band stays until the next boot; it is harmless once the bridges are gone.

```sh
ip rule show | awk -F: '/iif vn-/ { print $1 }' | xargs -rn1 sudo ip rule del pref
```

WARP itself is covered in [WARP on the fleet](../apps/cloudflare/warp/README.md).
