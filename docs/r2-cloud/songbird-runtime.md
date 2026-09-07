# Songbird Runtime

## Scope

Document the `songbird` host policy for `r2-flake` consumption and the
runtime contract applied by the shared builder.

## Source of Truth

- `modules/songbird/r2-runtime.nix` (host policy)
- `modules/songbird/policy.nix` (readiness gate)
- `modules/songbird/hardware-config.nix` (`/data` filesystem)
- `modules/lib/r2-runtime.nix` (shared runtime contract)
- `modules/hosts/common/imports.nix` (secrets module defaults)

## Not Covered

- Producer option defaults and full schema table
  (see upstream `docs/reference/index.md`)
- Duplicati backup service (`services.duplicati-r2`)

## Current Host Policy

`modules/songbird/r2-runtime.nix` builds the host module through
`config.flake.lib.nixos.r2.mkHostR2Module` with:

- `enableExternalFlake = flake.lib.nixos.hosts.songbird.r2RuntimeReady`
- `sopsRuntimeReady = flake.lib.nixos.hosts.songbird.r2RuntimeReady`
- `disabledReason` explaining how to restore the readiness flag and encrypted
  payload if either is unavailable

`modules/songbird/policy.nix` sets `r2RuntimeReady = true`. The common
baseline also defaults `security.r2CloudSecrets.enable` and
`home.r2Secrets.enable` on, so with a present `secrets/r2.yaml` the helper
imports the producer's NixOS and Home Manager modules, provisions the `/data`
runtime paths, and assigns the runtime services below.

## Data Volume Contract

`modules/songbird/hardware-config.nix` mounts `/data` from
`/dev/mapper/data`, an XFS filesystem on a LUKS2-encrypted SATA drive, with
`nofail` so an absent or unopened volume does not block boot. The
`r2-runtime-paths` provisioning unit and every writer unit carry
`After=data.mount` and `ConditionPathIsMountPoint=/data` (the shared mount
gate from `modules/git/mirror-root.nix`), so they stay inactive instead of
writing under `/data` on the root filesystem when the volume is not mounted.

## Services and Programs

The following contract is configured in `modules/lib/r2-runtime.nix`:

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
   - bisync start timeout: `20m`
2. `fonts`
   - bucket: `nix-r2-cf-r2e-files-prod`
   - remote prefix: `fonts`
   - mount point: `/data/r2/mount/fonts`
   - local path: `/data/fonts`
   - sync interval: `30m`
   - bisync start timeout: `20m`
3. `docs`
   - bucket: `nix-r2-cf-r2e-files-prod`
   - remote prefix: `docs`
   - mount point: `/data/r2/mount/docs`
   - local path: `/data/Docs`
   - sync interval: `5m`
   - bisync start timeout: `6h`

## Restic Profile

- bucket: `nix-r2-cf-backups-prod`
- paths: `/data/r2/workspace`
- credentials/account/password paths all sourced from `/run/secrets/r2/*`

## Runtime Ownership

`programs.fuse.userAllowOther = true` is set. Service units run as the `vx`
user/group for:

- `r2-mount-workspace`
- `r2-bisync-workspace`
- `r2-mount-fonts`
- `r2-bisync-fonts`
- `r2-mount-docs`
- `r2-bisync-docs`
- `r2-restic-backup`

`modules/lib/r2-runtime.nix` asserts the guarded writer set in both
directions: every name above must render an `ExecStart`, and every unit in
`systemd.services` with an `r2-` prefix must belong to that set, so an
`r2-flake` unit added without a matching entry fails evaluation instead of
shipping without the `/data` mount gate.

## Quick Verification

```bash
rg -n 'mkHostR2Module|enableExternalFlake|sopsRuntimeReady' modules/songbird/r2-runtime.nix
rg -n 'services\.r2-sync|services\.r2-restic|programs\.git-annex-r2|programs\.fuse\.userAllowOther' modules/lib/r2-runtime.nix
rg -n 'r2-(mount|bisync|restic)' modules/lib/r2-runtime.nix
```
