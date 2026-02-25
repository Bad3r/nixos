# System76 Runtime

## Scope

Document the current `system76` runtime contract that consumes `r2-flake`
modules.

## Source of Truth

- `modules/system76/r2-runtime.nix`

## Not Covered

- Producer option defaults and full schema table
  (see upstream `docs/reference/index.md`)
- Duplicati backup service (`services.duplicati-r2`)

## Enabled Services and Programs

| Surface                                   | Enabled | Key bindings in this repo                                                                     |
| ----------------------------------------- | ------- | --------------------------------------------------------------------------------------------- |
| `services.r2-sync`                        | yes     | `credentialsFile=/run/secrets/r2/credentials.env`, `accountIdFile=/run/secrets/r2/account-id` |
| `services.r2-restic`                      | yes     | same credentials/account ID files + `passwordFile=/run/secrets/r2/restic-password`            |
| `programs.git-annex-r2`                   | yes     | `credentialsFile=/run/secrets/r2/credentials.env`                                             |
| `home-manager.users.vx.programs.r2-cloud` | yes     | `accountIdFile`, `credentialsFile`, `explorerEnvFile` all under `/run/secrets/r2`             |

## Sync Mount Profiles

Current configured mounts:

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
  - `r2-restic-backup`
- `systemd.tmpfiles` ensures `/data/r2` and required mount/workspace
  directories exist and are user-owned.

## Quick Verification

```bash
rg -n 'services\\.r2-sync|services\\.r2-restic|programs\\.git-annex-r2|programs\\.fuse\\.userAllowOther' modules/system76/r2-runtime.nix
rg -n 'r2-(mount|bisync|restic)' modules/system76/r2-runtime.nix
```
