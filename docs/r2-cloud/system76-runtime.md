# System76 Runtime

## Scope

Document the `system76` host policy for `r2-flake` consumption and the runtime
contract that applies when the policy enables it.

## Source of Truth

- `modules/system76/r2-runtime.nix` (host policy)
- `modules/lib/r2-runtime.nix` (shared runtime contract)
- `modules/system76/imports.nix` (secrets module toggles)

## Not Covered

- Producer option defaults and full schema table
  (see upstream `docs/reference/index.md`)
- Duplicati backup service (`services.duplicati-r2`)

## Current Host Policy

`modules/system76/r2-runtime.nix` builds the host module through
`config.flake.lib.nixos.r2.mkHostR2Module` with:

- `enableExternalFlake = false`
- `sopsRuntimeReady = false`
- `disabledReason` explaining that system76 R2 integration is disabled until
  the upstream `r2-flake` stops referencing removed `pkgs.nodePackages`

`modules/system76/imports.nix` additionally forces
`security.r2CloudSecrets.enable = false` and `home.r2Secrets.enable = false`
for the owner user. With this policy, no `r2-*` units, `/run/secrets/r2/*`
files, or `r2` wrapper are active on `system76`; the helper emits the
`disabledReason` as an evaluation warning instead.

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
