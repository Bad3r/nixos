# Workload links and host services

`workloads.host.services.<name>` names a listener on the host, and a guest's `links` opens a path from the guest to a host service or another guest.
`modules/workloads/sharing/` renders both into `inet workload`, `nixos-fw`, the egress rules, and gateway proxies.
The options are documented in `modules/workloads/sharing/options.nix`; isolation itself is covered in [Workload networks](workloads.md).

## Declare a host service

```nix
_: {
  configurations.nixos.<host>.module.workloads.host.services.<name> = {
    ports = [ <port> { from = <first>; to = <last>; } { port = <port>; proto = "udp"; } ];
    bind = "any";
    grantable = true;
  };
}
```

- A declaration opens nothing; only a link or a grant does.
- `bind = "any"` is for a service that listens on every address, so guests reach it at their gateway.
- `bind = "loopback"` is for a service bound to 127.0.0.1; it never rebinds, and `route_localnet` stays off.
  Each linked network gets a `systemd-socket-proxyd` on its gateway, so its ports are single TCP ports.
- `grantable` lets runtime grants open the service; links do not need it.

## Declare a link

```nix
workloads.guests.<guest>.links = [ "host:<service>" "guest:<name>:<port>" "host:<service>:<port>/udp" ];
```

| Target                     | Reaches                    |
| -------------------------- | -------------------------- |
| `host:<service>`           | the service at the gateway |
| `guest:<name>`             | the guest at its address   |
| `service:<name>`           | a container at its address |
| `:<port>` or `:<port>/udp` | one port instead of all    |

- Without a port, a link opens every port the target declares: a host service's `ports`, a guest's `grantable`, or a container's `ports`.
  A guest target without `grantable` ports needs an explicit port; `grantable` gates runtime grants only.
- A port on a host service target must lie inside one of the service's `ports`.
- Untrusted guests reach host services through grants only, so a `host:` link on one fails evaluation.
- Sandboxes are runtime objects and take grants, never links.
- Only guests are link sources; containers are targets.
- A target on several networks is reached at its address on the guest's network, else on its alphabetically first interface.
- Inside the guest, a host service answers at the gateway address.

Evaluation fails on an unknown target, an undeclared port, or a guest target on the same `isolatePeers` network, whose bridge table drops traffic between peers.
A target on the guest's own network without `isolatePeers` already reaches it and gets no rule.

## What a link renders

- `host:` link: an `inet workload` input accept from the guest address to the gateway on the service ports, plus the ports in `networking.firewall.interfaces.<bridge>` so `nixos-fw` accepts them too.
- `guest:` or `service:` link across networks: a forward accept on source bridge, destination bridge, both addresses, protocol, and port for `ct state new`, ahead of the cross-network drop; replies ride conntrack.
  `workload-egress.service` adds an `ip rule` per direction that sends the peer address to the main table ahead of the WARP lookup.
- Loopback service: `workload-proxy-<network>-<service>-<port>.socket` listens on the gateway with `FreeBind=yes`, so it binds before the runtime creates the bridge.
  The socket accepts only the linked guests' addresses.

Removing a link leaves established connections in conntrack until they close or expire; `sudo conntrack -D -s <guest address>` clears them.

## Address pinning

Rules match the source address, so `bridge workload-addresses` (`modules/workloads/vms/addresses.nix`) pins each declared guest address to its guest.
Each declared interface gets a tap named `vg-<hash>` from the UUID and interface name, and that tap may send only its own MAC and address, plus DHCP from 0.0.0.0.
Every other port of the bridge is dropped when it claims a declared address, in IP or ARP, whether or not the owner is running.
No port may claim the gateway address.

## Verify

Run as the owner on the host:

```sh
sudo nft list chain inet workload input
sudo nft list chain inet workload forward
sudo nft list chain inet nixos-fw input-allow | grep vn-
ip rule | grep 'lookup main'
systemctl list-sockets 'workload-proxy-*'
```

From inside a linked guest, with the gateway of its network:

```sh
nc -vz <gateway> <port>
```

## Link times out

Cause: the guest's address differs from its reservation, the target listens elsewhere, or the generation with the link is not active.

```sh
ip neigh show dev vn-<network>
sudo nft list chain inet workload input | grep <guest address>
ss -ltnp | grep <port>
```

Fix: renew the guest's DHCP lease, bind the service as its `bind` says, or switch to the generation that declares the link.

## Loopback service refuses connections

Cause: the proxy reaches 127.0.0.1 only, so a service on `::1` or another address is not found.

```sh
systemctl status 'workload-proxy-*'
journalctl -u 'workload-proxy-*' -n 20
```

Fix: bind the service to 127.0.0.1, or declare it `bind = "any"` when it listens on every address.
