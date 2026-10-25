# Workload grants

A grant opens one path from a sandbox or a declared guest to a host service, a guest, or a container service, for a bounded time and without a prompt.
`workloads.grants.allow` in `modules/hosts/<host>/workloads.nix` bounds what `workloads grant` may open; [grants.nix](../../modules/workloads/sharing/grants.nix) holds the options and renders the table, the helper, and the policy file.
Declared, lasting paths are [links](workload-links.md); sandboxes take grants only.

## Declare grant rules

```nix
_: {
  configurations.nixos.<host>.module.workloads.grants = {
    allow = [
      { from = [ "sbx-*" ]; to = [ "host:<service>" "guest:<name>:<port>" ]; maxTtl = "2h"; }
      { from = [ "guest:<name>" ]; to = [ "host:<service>" ]; maxTtl = "24h"; }
    ];
    maxConcurrent = 8;
  };
}
```

- `from` names `sbx-*`, every sandbox, or `guest:<name>`, a present guest.
- `to` uses the link target grammar; a port narrows the entry to that port.
- A host service target must be `grantable`; a guest target opens only its `grantable` ports, and a container service its declared ports.
- `maxConcurrent` bounds the live grants at each source address, whatever name the caller gives.
- Evaluation fails on an unknown source or target, an ungrantable service, a port outside the target's grantable ports, or a sandbox network without `libvirt.bindLeases`.

A sandbox is a grant source on a network with `libvirt.sessionAttach`, identified by its address and the MAC of its live DHCP lease there.
A guest source is identified by its declared address and MAC; on a network without lease binding, its peers are trusted not to claim them.
LAN, Mesh, and internet destinations cannot be named, so they are never grantable.

## Grant from the command line

Run as the owner on the host:

```sh
workloads grant sbx-<name> host:<service> --ttl 30m
workloads grant <guest> guest:<name>:<port>
workloads grants
workloads revoke <id>
workloads revoke --all sbx-<name>
```

- A source is `sbx-<name>`, `guest:<name>`, or a bare guest name; for a sandbox, the command reads its address from `sbx info`.
- Without a port, the grant opens every grantable port of the target, which for a range is every listener in it.
- `--ttl` takes `s`, `m`, `h`, or `d`; the default is 30 minutes, and the rule's `maxTtl` caps it.
- A grant permits all traffic on its path, established connections included, only until its TTL ends.
  When it expires or is revoked, every connection it admitted stops at once; connections of other grants keep working.
- An expired grant is gone, so `revoke` answers `not-found` for it.
- `revoke --all` takes the grants at the source's address and those made under its name; `sbx destroy` and `sbx gc` run it for each sandbox they remove.
- Every verb takes `--json`; failures print `{"error": {"code", "message"}}` and exit 1, or 2 for `usage`.

| Code                | Cause                                    |
| ------------------- | ---------------------------------------- |
| `not-allowed`       | no rule names the source and target      |
| `not-grantable`     | port or target outside the grantable set |
| `already-reachable` | the target shares the source's bridge    |
| `ttl`               | TTL above the rule's `maxTtl`            |
| `max-concurrent`    | the address holds `maxConcurrent` grants |
| `conflict`          | an overlapping or earlier holder's grant |
| `no-address`        | the sandbox sits on no workload network  |
| `no-lease`          | no live DHCP lease holds the address     |
| `lease-file`        | the lease file does not parse            |
| `not-found`         | no live grant has the id                 |
| `invalid-target`    | the target does not parse                |
| `invalid-source`    | the source does not parse or fit         |
| `invalid-request`   | the helper's request grammar refused it  |
| `policy-file`       | `/etc/workloads/grants.json` is broken   |
| `journal`           | the journal refused the record           |
| `nft`, `route`      | the grant table or rules are unusable    |
| `conntrack`         | ended grants' entries were not removed   |
| `no-helper`         | no grant rule or present guest declared  |
| `helper`            | the helper answered no JSON object       |
| `sbx`               | `sbx info` failed                        |
| `os-error`          | the socket refused the caller            |
| `usage`             | the command line does not parse          |

## What a grant renders

- One element per port range in the `grants` set of `inet workload_grants`, keyed on ingress bridge, source address, destination address, protocol, and ports, with the TTL as its timeout.
- One element in its `sources` set binds the ingress bridge and source address to the source's MAC for as long as its longest grant lives.
- The table's chains run one priority ahead of `inet workload` and mark the conntrack entry of each new connection that matches both sets.
- They cut every packet of a marked connection whose original tuple has left `grants`, in both directions: a TCP segment draws a reset to its sender, anything else is dropped.
- They drop every packet a marked connection sends from a MAC `sources` does not bind.
- They drop every forwarded packet of a marked connection that would leave through anything but a `vn-*` bridge, established ones included, so a grant never follows the default route to the uplink.
- `inet workload` accepts the mark ahead of its drops, and `nixos-fw` accepts it too, since a drop in any base chain is final.
- A host service answers at the gateway of the source's network; a loopback service gets a gateway proxy on every network a rule's sources sit on.
- A grant between two networks adds an `ip rule` each way ahead of the `workload-egress` band; the next grant or revoke removes the rules of expired grants.
- Revoke removes only elements and routes, so its connections keep their marked conntrack entries and stay cut, as at expiry.
- A grant first deletes the marked entries an ended grant left on its paths, so it carries only connections that start under it.
- Once a TCP entry is gone, [`inet workload`](workloads.md) drops the flow's next segment, so an ended TCP connection never passes again.
- A UDP flow has no such guard: after its entry times out, a datagram from the source needs a live grant, and one the host sends is host-to-guest traffic, which grants do not govern.

## Survival across reloads

`networking.nftables.tables` reloads delete and recreate each declared table, which would empty the sets, so the grant table stays outside them.
`workload-grants.service` owns it and loads it with `add` and `flush chain` only, which keeps the elements; a switch, an `nftables` reload or restart, and a restart of the unit all leave live grants in place and ended ones cut.
An `nftables` reload propagates to the unit, which recreates the chains when something deleted the table.
A change to a set's type fails the unit until the table is recreated.
With no rule and no present guest declared, the unit empties the set, deletes the marked conntrack entries, and deletes the table and the grant routes instead.

## The helper

`workload-grantd.socket` listens on `/run/workloads/grant.sock`, owned by the owner and mode 0600, so only the owner and root connect.
Each connection starts one `workload-grantd@` instance as root with `CAP_NET_ADMIN` as its only capability.
It reads one JSON request, checks it against `/etc/workloads/grants.json` and the sandbox network's lease file, and only adds or removes set elements, the marked conntrack entries of ended grants, the grant routes, and [runtime shares](workload-shares.md).
Before it applies a decision, it journals the caller's pid, uid, and command line, the agent session the client reports, and the decision.

The allowlist is a guard rail, not a boundary, while the owner holds root-equivalent groups.

## Verify

Run as the owner on the host:

```sh
workloads grants
sudo nft list table inet workload_grants
sudo nft list chain inet workload input | grep 'ct mark'
systemctl status workload-grants.service workload-grantd.socket
journalctl -t workload-grant -n 20
```

## Grant succeeds but the connection times out

Cause: the service listens elsewhere, the sandbox took a new lease since the grant, or the route for a cross-network grant is missing.

```sh
sudo nft list set inet workload_grants grants
ip rule | grep 'lookup main'
ss -ltnp | grep <port>
```

Fix: bind the service as its `bind` says, or revoke and grant again so the helper reads the current lease and restores the routes.

## Every grant fails with nft

Cause: `workload-grants.service` failed, so the table is missing or holds an older set type.

```sh
systemctl status workload-grants.service
journalctl -u workload-grants.service -n 20
```

Fix: recreate the table, which drops every live grant:

```sh
sudo nft delete table inet workload_grants
sudo systemctl restart workload-grants.service
```
