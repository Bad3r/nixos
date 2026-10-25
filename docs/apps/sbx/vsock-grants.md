# sbx vsock grants

A sandbox created with `--net none` has no address, so a [workload grant](../../networking/workload-grants.md) reaches it over vsock instead of through the grant table.
`workloads grant sbx-<name> host:<service>[:<port>]` opens the service's granted TCP ports to that sandbox alone.
Inside the guest, a granted port is vsock CID 2 at the service's own port number, which Python's `socket.AF_VSOCK` and `socat VSOCK-CONNECT:2:<port>` reach.

```sh
workloads grant sbx-probe host:dev:8080 --ttl 30m
```

## How a grant is served

- `workload-grantd` checks the request against the same rules, `grantable` ports, `maxTtl`, and `maxConcurrent` as address grants, and refuses guest and container targets and UDP ports.
- It records the grant, with the sandbox's name and creation token, in `/run/workloads/vsock-grants.json`, root-owned and world-readable.
- The owner's `sbx-vsock.service`, started on demand by `sbx-vsock.socket`, reads that list (`packages/sbx/sbx/vsock.py`).
- For each live grant it forks a child that joins the user and network namespace of the sandbox's QEMU through a pidfd.
  The child creates one vsock listener per port there and passes the descriptors back.
- The service itself stays in the host's namespace and forwards each accepted connection to the granted port from there.
  A `bind = "loopback"` service is reached on `127.0.0.1` and sees the connection from `127.0.0.1`.
  A `bind = "any"` service is reached on the host's first non-loopback IPv4 address, by interface index, and sees the connection from it.
  A loopback-only listener in its range is therefore out of reach; without such an address, the connection closes.
- Connections are capped per grant and per sandbox (`packages/sbx/sbx/vsock.py`); past a cap, new connections wait in the listener's backlog.
- A full descriptor table pauses a grant's accepting for a second instead of stopping the proxy.
- `workloads grant` returns only once `sbx vsock sync` reports the grant's listeners placed; otherwise it revokes the grant and fails with `vsock-listener`.

## Lifecycle

| Event                       | Effect                                    |
| --------------------------- | ----------------------------------------- |
| revoke, `sbx destroy`, `gc` | listeners and connections close           |
| TTL ends                    | listeners and connections close           |
| QEMU exits, `sleep save`    | listeners and connections close           |
| `sleep restore`             | fresh listeners in the new namespace      |
| proxy stops or crashes      | all its connections and listeners close   |
| proxy starts again          | listeners rebuilt from the list           |
| last grant rule removed     | the list goes, and with it every listener |

- `workloads revoke` returns once the proxy has closed the revoked grants' listeners and connections.
  When the proxy does not confirm, it fails with `vsock-unconfirmed`; the grant is already gone from the list.
- The TTL counts on the boot clock, so host sleep counts against it.
- A grant names one sandbox creation: a later sandbox of the same name never inherits it.
- `workloads grant` asks for a vsock grant only for a sandbox without an address.
  The helper cannot see a sandbox's network, so a caller that sends an egress sandbox's token gets one under the same policy.

## Fail closed

The proxy exposes nothing for a grant when:

- the sandbox's run directory holds another creation token;
- libvirt's pid file names no QEMU of that domain;
- the namespace is the host's, or its vsock mode is not `local`;
- the list is unreadable, malformed, or writable by anyone but root.

A placement that fails is retried every second while the grant lives, and `sbx vsock sync --json` shows each grant's state and error.

## Trust

The grant authority is `workload-grantd`, which runs as root with `CAP_NET_ADMIN` only and never enters a namespace.
The proxy runs as the owner, because only the namespace's owner can join it without `CAP_SYS_ADMIN`.
Agents run as the owner too, and the owner can join a sandbox's namespace and listen there without any grant.
Vsock grants are therefore a guard rail for well-behaved callers, not a boundary.

## Verify

As the owner:

```sh
workloads grants
sbx vsock sync --json
systemctl --user status sbx-vsock.socket sbx-vsock.service
journalctl --user -t sbx -g vsock -n 20
```

## Grant fails with vsock-listener

Cause: the sandbox is not running, was replaced, or its QEMU namespace is not a `local` vsock namespace.

```sh
sbx info <name> --json
sbx vsock sync --json
journalctl --user -t sbx -g vsock -n 20
```

Fix: start or recreate the sandbox, or fix the namespace mode as in [troubleshooting](troubleshooting.md), then grant again.
