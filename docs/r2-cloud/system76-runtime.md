# System76 Runtime

## Scope

Document the `system76` host policy for `r2-flake` consumption and the runtime
contract that applies when the policy enables it.

## Source of Truth

- `modules/system76/r2-runtime.nix` (host policy)
- `modules/lib/r2-runtime.nix` (shared runtime contract)
- `modules/hosts/common/imports.nix` (secrets module defaults)

## Not Covered

- Producer option defaults and full schema table
  (see upstream `docs/reference/index.md`)
- Duplicati backup service (`services.duplicati-r2`)

## Current Host Policy

`modules/system76/r2-runtime.nix` builds the host module through
`config.flake.lib.nixos.r2.mkHostR2Module` with:

- `enableExternalFlake = flake.lib.nixos.hosts.system76.r2RuntimeReady`
- `sopsRuntimeReady = flake.lib.nixos.hosts.system76.r2RuntimeReady`
- `disabledReason` explaining how to restore the readiness flag and encrypted
  payload if either is unavailable

`modules/system76/policy.nix` currently sets `r2RuntimeReady = true`, and the
common baseline defaults `security.r2CloudSecrets.enable` and
`home.r2Secrets.enable` on. With `secrets/r2.yaml` present, the evaluated
configuration imports both producer modules and enables the `r2-*` units,
runtime secret files, and the owner user's `r2` wrapper. If readiness or the
encrypted payload is missing, the helper omits runtime assignments and emits
`disabledReason` as an evaluation warning.

## Services and Programs When the Policy Enables the Runtime

Configured in `modules/lib/r2-runtime.nix`:

| Surface                                   | Key bindings in this repo                                                                                 |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `services.r2-sync`                        | `credentialsFile=/run/secrets/r2/credentials.env`, `accountIdFile=/run/secrets/r2/account-id`             |
| `services.r2-restic`                      | same credentials/account ID files + `passwordFile=/run/secrets/r2/restic-password`                        |
| `programs.git-annex-r2`                   | `credentialsFile=/run/secrets/r2/credentials.env`                                                         |
| `home-manager.users.vx.programs.r2-cloud` | `accountIdFile`, `credentialsFile`, `explorerEnvFile` under `/run/secrets/r2`; `enableRcloneRemote=false` |

## Sync Mount Profiles

Configured mounts (in `modules/lib/r2-runtime.nix`):

1. `workspace`
   - bucket: `nix-r2-cf-r2e-files-prod`
   - remote prefix: `workspace`
   - mount point: `/data/r2/mount/workspace`
   - local path: `/data/r2/workspace`
   - sync interval: `5m`
2. `fonts`
   - bucket: `nix-r2-cf-r2e-files-prod`
   - remote prefix: `fonts`
   - mount point: `/data/r2/mount/fonts`
   - local path: `/data/fonts`
   - sync interval: `30m`
3. `docs`
   - bucket: `nix-r2-cf-r2e-files-prod`
   - remote prefix: `docs`
   - mount point: `/data/r2/mount/docs`
   - local path: `/data/Docs`
   - sync interval: `5m`

## Restic Profile

- bucket: `nix-r2-cf-backups-prod`
- paths: `/data/r2/workspace`
- credentials/account/password paths all sourced from `/run/secrets/r2/*`

## Runtime Ownership and Filesystem Contract

- `programs.fuse.userAllowOther = true` is enabled.
- Service units run as `vx` user/group for:
  - `r2-mount-workspace`
  - `r2-bisync-workspace`
  - `r2-mount-fonts`
  - `r2-bisync-fonts`
  - `r2-mount-docs`
  - `r2-bisync-docs`
  - `r2-restic-backup`
- `systemd.tmpfiles` ensures `/data/r2`, the mount points, `/data/r2/workspace`,
  `/data/fonts`, and `/data/Docs` exist and are user-owned.

## Quick Verification

```bash
rg -n 'mkHostR2Module|enableExternalFlake|sopsRuntimeReady' modules/system76/r2-runtime.nix
rg -n 'services\.r2-sync|services\.r2-restic|programs\.git-annex-r2|programs\.fuse\.userAllowOther' modules/lib/r2-runtime.nix
rg -n 'r2-(mount|bisync|restic)' modules/lib/r2-runtime.nix
```
