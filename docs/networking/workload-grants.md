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
- `maxConcurrent` bounds the live grants of each source.
- Evaluation fails on an unknown source or target, an ungrantable service, or a port outside the target's grantable ports.

Sandboxes are grant sources on a network with `libvirt.sessionAttach`; the helper accepts only addresses on such a network that no declared object holds.
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

- A source is `sbx-<name>`, `guest:<name>`, or a bare guest name.
- Without a port, the grant opens every grantable port of the target.
- `--ttl` takes `s`, `m`, `h`, or `d`; the default is 30 minutes, and the rule's `maxTtl` caps it.
- Every verb takes `--json`; failures print `{"error": {"code", "message"}}` and exit 1.
- For a sandbox, the command reads its address from `sbx info`.

| Code             | Cause                                    |
| ---------------- | ---------------------------------------- |
| `not-allowed`    | no rule names the source and target      |
| `not-grantable`  | port or target outside the grantable set |
| `ttl`            | TTL above the rule's `maxTtl`            |
| `max-concurrent` | the source holds `maxConcurrent` grants  |
| `conflict`       | another grant covers an overlapping path |
| `no-address`     | the sandbox sits on no workload network  |
| `os-error`       | the socket refused the caller            |

## What a grant renders

- One element per port range in the set of `inet workload_grants`, keyed on ingress bridge, source address, destination address, protocol, and ports, with the TTL as its timeout.
- The table's input and forward chains run one priority ahead of `inet workload` and mark the conntrack entry of each new connection that matches.
- `inet workload` accepts the mark ahead of its drops, and `nixos-fw` accepts it too, since a drop in any base chain is final.
- A host service answers at the gateway of the source's network; a loopback service gets a gateway proxy on every network a rule's sources sit on.
- A grant between two networks adds an `ip rule` each way ahead of the `workload-egress` band; the next grant or revoke removes the rules of expired grants.

An established connection keeps its mark when the grant expires, until it closes.
`workloads revoke` deletes the elements and then the marked conntrack entries on their ports, so a revoked connection stops at once.

## Survival across reloads

`networking.nftables.tables` reloads delete and recreate each declared table, which would empty the set, so the grant table stays outside them.
`workload-grants.service` owns it and loads it with `add` and `flush chain` only, which keeps the elements; a switch, an `nftables` reload or restart, and a restart of the unit all leave live grants in place.
An `nftables` reload propagates to the unit, which recreates the chains when something deleted the table.
A change to the set's type fails the unit until the table is recreated, as in the last section.

## The helper

`workload-grantd.socket` listens on `/run/workloads/grant.sock`, owned by the owner and mode 0600, so only the owner and root connect.
Each connection starts one `workload-grantd@` instance as root with `CAP_NET_ADMIN` as its only capability.
It reads one JSON request, checks it against `/etc/workloads/grants.json`, and only adds or removes set elements, conntrack entries, and the grant routes.
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

## Grant answers no-address

Cause: the sandbox was created without a network, so `sbx info` reports no address.

```sh
sbx info <name> --json
```

Fix: create the sandbox on a network that sandboxes attach to.

## Grant succeeds but the connection times out

Cause: the service listens elsewhere, the source's address differs from the one granted, or the route for a cross-network grant is missing.

```sh
sudo nft list set inet workload_grants grants
ip rule | grep 'lookup main'
ss -ltnp | grep <port>
```

Fix: bind the service as its `bind` says, or revoke and grant again so the helper reads the current address and restores the routes.

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
