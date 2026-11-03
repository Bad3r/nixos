# OpenShell

`openshell` creates agent sandboxes through the `openshell-gateway` user service ([nixos.nix](../../modules/apps/openshell/nixos.nix), [home.nix](../../modules/apps/openshell/home.nix)).
The gateway admits only mTLS clients holding its client bundle, and every holder controls it fully: sandboxes, providers, and rule approvals.
Upstream docs: <https://docs.nvidia.com/openshell/latest/>

## Register the gateway on the host

Precondition: `openshell-gateway` is active, which generates the PKI on first start.

Register it as the owner:

```sh
openshell gateway add --local https://127.0.0.1:17670
```

Verify with `openshell status`, which reports `Authenticated (mTLS transport)`.

## Connect from a Mesh peer or a workload VM

Precondition: the client runs an `openshell` CLI of the gateway's release.
The server certificate names `host.openshell.internal`, so a client dials that name and maps it to its own route to the host.

1. Copy the bundle from the host's `~/.config/openshell/gateways/openshell/mtls/` to the same path under the client user's home.

2. Add a hosts entry on the client.
   A Mesh peer maps the name to the host's Mesh address, and a VM to the gateway address of its workload network (`workloads.networks`):

   ```text
   <address> host.openshell.internal
   ```

3. A workload VM also needs a grant, run as the owner on the host:

   ```sh
   workloads grant <guest> host:openshell --ttl 8h
   workloads grant sbx-<name> host:openshell --ttl 2h
   ```

   The grant rules live in `modules/hosts/songbird/workloads.nix`; [workload grants](../networking/workload-grants.md) covers TTLs and revocation.

4. Register the gateway on the client:

   ```sh
   openshell gateway add https://host.openshell.internal:17670 --remote <user>@<host> --name openshell
   ```

   `--name openshell` matches the bundle's directory; `--remote` only labels the registration.

Verify with `openshell status` on the client, which reports `Authenticated (mTLS transport)`.

## Revoke access

The bundle cannot be revoked per client.
Stop `openshell-gateway`, delete `~/.local/state/openshell/tls/` and the host's bundle directory, then start the service to issue a new PKI and copy the new bundle to the clients that keep access.
