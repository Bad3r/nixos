# Untrusted containers with Podman

`podman --module untrusted` runs a container under gVisor with no network, for MCP images and one-shot tools pulled from the internet.
The `untrusted` containers.conf module ships with the podman app in [nixos.nix](../../modules/apps/podman/nixos.nix).
Plain rootless containers carry the owner's own trust: their traffic leaves as the owner's sockets and reaches host listeners, the LAN, and Mesh.

## Run an untrusted container

`--module` is a root-level flag, so it goes before the subcommand:

```sh
podman --module untrusted run --rm <image> <command>
```

Speak to an MCP server over stdio:

```sh
podman --module untrusted run -i --rm <image>
```

Hand the container a host Unix socket by mounting its directory:

```sh
podman --module untrusted run --rm -v "$PWD/sock:/sock" <image>
```

The `docker` shim is the podman CLI, so `docker --module untrusted run` behaves the same.

## What the tier fences

- The container sees only a loopback interface: no Internet, LAN, Mesh, or host listeners, and no `/etc/resolv.conf`.
- gVisor answers the container's system calls, so a kernel exploit has to break gVisor first.
- No host environment variables enter the container.
- Bind-mounted host Unix sockets accept connections; nothing else on the host is reachable without a mount.
- The gVisor sandbox runs as the owner, so an escape from gVisor lands with the owner's rights.

## Limits

- Docker API clients cannot use the tier: the compat API ignores runtime selection, so `docker` over a socket, docker-compose, lazydocker, and API-driven MCP launchers run under crun.
- No GPU: gVisor's nvproxy rejects the installed NVIDIA driver branch.
- Cgroup limits such as `--memory` and `--cpus` are not enforced, because runsc runs with `ignore-cgroups` under rootless Podman.
- A `--network` or `--runtime` flag on the command line overrides the module and leaves the tier.
- `--userns=nomap` fails under runsc, and `--userns=auto` needs more subordinate IDs than the owner has.
- Untrusted work that needs a network belongs in a VM, not here.

## Verify the tier

The kernel version is gVisor's, not the host's, and the network probe fails:

```sh
podman --module untrusted run --rm alpine uname -r
podman --module untrusted run --rm alpine wget -T 5 -qO- http://1.1.1.1
```

Upstream reference: <https://gvisor.dev/docs/>
