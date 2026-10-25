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
- The service itself stays in the host's namespace and forwards each accepted connection to the port on `127.0.0.1`, where both `bind` modes answer.
- `workloads grant` returns only once `sbx vsock sync` reports the grant's listeners placed; otherwise it revokes the grant and fails with `vsock-listener`.

## Lifecycle

| Event                        | Effect                                    |
| ---------------------------- | ----------------------------------------- |
| revoke, `sbx destroy`, `gc`  | listeners and connections close           |
| TTL ends                     | listeners and connections close           |
| QEMU exits, `sleep save`     | listeners and connections close           |
| `sleep restore`              | fresh listeners in the new namespace      |
| `sbx-vsock.service` restarts | connections drop; listeners come back     |
| last grant rule removed      | the list goes, and with it every listener |

- `workloads revoke` returns once the proxy has closed the revoked grants' listeners and connections.
- The TTL counts on the boot clock, so host sleep counts against it.
- A grant names one sandbox creation: a later sandbox of the same name never inherits it.

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
