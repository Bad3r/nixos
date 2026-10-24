# Workload networks

`workloads.networks.<name>` declares a bridge network for VMs and containers.
`modules/workloads/networks.nix` renders its firewall tables, IPv4 forwarding, and egress routing; the runtime that uses the network creates the bridge `vn-<name>` and serves DHCP on it.
A network is isolated by default: guests reach the gateway for DHCP, and for DNS on `warp` networks, and nothing else on the host, the LAN, Mesh, or another network.

## Table ownership

| Table                   | Owner           | Role                                     |
| ----------------------- | --------------- | ---------------------------------------- |
| `inet nixos-fw`         | NixOS firewall  | opens DHCP, DNS, host ports per bridge   |
| `inet workload`         | workload module | input pre-filter, forwarding, masquerade |
| `bridge workload-peers` | workload module | drops guest-to-guest on one bridge       |
| `inet cloudflare-warp`  | warp-svc        | admits the workload block on its own     |

The `inet workload` input chain runs one priority ahead of `nixos-fw`.
A drop in any base chain is final, so new traffic from a bridge never reaches the ports `nixos-fw` opens on every interface, and the pre-filter narrows the per-bridge opens to the gateway address.
The forward chain drops all forwarding that neither enters nor leaves a `vn-*` bridge, so turning forwarding on never makes the host a router between the LAN, Mesh, and WARP.
The module sets `net.ipv4.conf.all.forwarding` only while at least one network is declared.
It never loads `br_netfilter`; the rules behave the same with and without it.

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
- `lanAccess` lets guests open connections to the local network.
- `isolatePeers` drops traffic between guests on the same bridge; the host and egress keep working.

`bridge`, `subnet`, `gateway`, and `mtu` are read-only and derived from the name, the id, and the egress mode; runtime modules read them.
The bridge name must fit the kernel's interface name limit, which the option type enforces.

## Egress modes

- `warp`: traffic leaves through the WARP tunnel, masqueraded to the host's Mesh address.
  Destinations WARP excludes resolve through the main table without its default route, and the forward chain drops them unless `lanAccess` is set.
  With the tunnel gone the route is unreachable, so the network fails closed instead of falling back to the uplink.
  Guests resolve names through the gateway.
- `none`: the route is unreachable and the gateway answers no DNS, so the host resolver is no exfiltration channel.

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

## Forwarding and rules remain after removing every network

Cause: the unit has no stop action and `systemd-sysctl` sets only the keys it lists, so the band and IPv4 forwarding stay on until the next boot.
Forwarding without the `inet workload` forward chain lets the host route between its interfaces, so turn it off right away; the band is harmless once the bridges are gone.

```sh
sudo sysctl -w net.ipv4.conf.all.forwarding=0
ip rule show | awk -F: '/iif vn-/ { print $1 }' | xargs -rn1 sudo ip rule del pref
```

WARP itself is covered in [WARP on the fleet](../apps/cloudflare/warp/README.md).
