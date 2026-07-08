# Cloudflare WARP (Zero Trust)

Declarative Cloudflare WARP enrollment for this NixOS configuration. The
`programs.cloudflare-warp.extended` module runs the `warp-svc` daemon and enrolls
a device into the Cloudflare Zero Trust organization non-interactively, using a
service token delivered through a managed deployment file (`mdm.xml`).

## Documents

| Document                      | Purpose                                                    |
| ----------------------------- | ---------------------------------------------------------- |
| [Deployment](./deployment.md) | Operator runbook: dashboard prerequisites, secret, rollout |
| [Reference](./reference.md)   | Module options, mdm.xml parameters, sops layout            |
| [Modes](./modes.md)           | WARP mode comparison, DNS tradeoffs, split tunnels         |
| [Operations](./operations.md) | Runtime verification, coexistence checks, troubleshooting  |
| [Cheatsheet](./cheatsheet.md) | `warp-cli`, `warp-diag`, and service inspection commands   |

## What the module does

`modules/apps/cloudflare-warp.nix` is a thin wrapper over the upstream
`services.cloudflare-warp` NixOS service. When `programs.cloudflare-warp.extended`
is enabled it:

1. Enables `services.cloudflare-warp`, which runs `warp-svc` as root with
   `CAP_NET_ADMIN` and opens the WARP UDP port (2408 by default).
2. Declares three sops secrets (`organization`, `auth_client_id`,
   `auth_client_secret`) from `secrets/cloudflare-warp.yaml`, guarded by
   `builtins.pathExists` so a missing secret warns and runs `warp-svc`
   un-enrolled instead of failing evaluation.
3. Renders `/var/lib/cloudflare-warp/mdm.xml` from non-secret options plus sops
   placeholders, and installs it (mode 0600, root) via an `ExecStartPre` right
   before `warp-svc` starts.
4. Sets `networking.firewall.checkReversePath = "loose"` (the WARP interface
   trips strict reverse-path filtering).
5. Adds a best-effort `cloudflare-warp-connect` oneshot that waits for the daemon
   and runs `warp-cli connect` on boot.

`service_mode` is authoritative through `mdm.xml`; the module never calls
`warp-cli mode`, so the managed config and the local client cannot fight.

## Enrolled hosts

| Host       | Service mode         | Enable file                            |
| ---------- | -------------------- | -------------------------------------- |
| `tpnix`    | `warp` (full tunnel) | `modules/tpnix/cloudflare-warp.nix`    |
| `system76` | `warp` (full tunnel) | `modules/system76/cloudflare-warp.nix` |

The common baseline (`modules/hosts/common/apps-enable.nix`) defaults the app
OFF; enrollment is a deliberate per-host opt-in. `system76` enables the wrapper
directly. `tpnix` gates `enable` on `flake.lib.nixos.hosts.tpnix.sopsRuntimeReady`
(currently `true` since repo-managed sops landed for tpnix in PR #305,
`modules/tpnix/policy.nix`), like its other sops consumers, so both hosts run
the wrapper un-enrolled until `secrets/cloudflare-warp.yaml` is committed. The
gate remains a kill switch: if tpnix ever loses its runtime decryption key,
flipping the flag back to `false` also drops the `cloudflare-warp/*` secret
declarations that would otherwise fail activation on an un-decryptable payload.

## Security model

- The team name (`organization`) and service-token credentials live only in
  `secrets/cloudflare-warp.yaml` (sops, age). The rendered `mdm.xml` is produced
  from sops placeholders, so neither the team name nor the credentials enter the
  Nix store or git history.
- `mdm.xml` is written to `/var/lib/cloudflare-warp/mdm.xml` as `0600 root:root`.
- `secrets/` is a git submodule; the encrypted payload is committed there, the
  Nix changes in the main repository.

## References

- [WARP client docs](https://developers.cloudflare.com/warp-client/)
- [Get started on Linux](https://developers.cloudflare.com/warp-client/get-started/linux/)
- [Deploy the client headless on Linux](https://developers.cloudflare.com/cloudflare-one/tutorials/deploy-client-headless-linux/)
- [Managed deployment parameters](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/deployment/mdm-deployment/parameters/)
- [Service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-auth/service-tokens/)
- [NixOS option `services.cloudflare-warp`](https://search.nixos.org/options?query=services.cloudflare-warp)
