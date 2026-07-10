# Secrets and Rendered Files

## Scope

Document how `secrets/r2.yaml` is transformed into runtime files used by
system services and the `r2` CLI wrapper.

## Source of Truth

- `modules/security/sops-policy.nix`
- `modules/security/r2-cloud-secrets.nix`
- `modules/home/r2-secrets.nix`
- `modules/lib/r2-runtime.nix`

## Not Covered

- Generic SOPS workflows and editor usage (see `../sops/README.md`)
- Non-R2 secret files

## Policy and Source File

- SOPS policy includes explicit creation rule `path_regex: secrets/r2\.yaml`.
- Source of truth file: `secrets/r2.yaml`.
- System declarations are gated by `security.r2CloudSecrets.enable`
  (default `false`) and guarded by
  `builtins.pathExists "${secretsRoot}/r2.yaml"`.
- The common baseline (`modules/hosts/common/imports.nix`) defaults the gate
  on for every shared host; per-host modules can override it.

## System Secret Mapping (`/run/secrets/r2/*`)

| YAML key in `secrets/r2.yaml` | Declared secret path                    | Primary consumers                                             |
| ----------------------------- | --------------------------------------- | ------------------------------------------------------------- |
| `account_id`                  | `/run/secrets/r2/account-id`            | `services.r2-sync`, `services.r2-restic`, `programs.r2-cloud` |
| `access_key_id`               | `/run/secrets/r2/access-key-id`         | `r2-credentials.env` template                                 |
| `secret_access_key`           | `/run/secrets/r2/secret-access-key`     | `r2-credentials.env` template                                 |
| `restic_password`             | `/run/secrets/r2/restic-password`       | `services.r2-restic.passwordFile`                             |
| `explorer_admin_kid`          | `/run/secrets/r2/explorer-admin-kid`    | `r2-explorer.env` template                                    |
| `explorer_admin_secret`       | `/run/secrets/r2/explorer-admin-secret` | `r2-explorer.env` template                                    |

Rendered templates:

- `/run/secrets/r2/credentials.env`
  - `R2_ACCOUNT_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- `/run/secrets/r2/explorer.env`
  - `R2_EXPLORER_BASE_URL`, `R2_EXPLORER_ADMIN_KID`, `R2_EXPLORER_ADMIN_SECRET`

Permissions:

- system secret files are mode `0400`
- owner is `metaOwner.username` (user `vx` in this repo)

## Home Manager R2 Env Template

Consumer-local HM module `flake.homeManagerModules.r2Secrets` also reads
`secrets/r2.yaml` (when `home.r2Secrets.enable` is set for the user) and
renders:

- `~/.config/cloudflare/r2/env` (mode `0400`)

with:

- `R2_ACCOUNT_ID`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

This HM env file exists for user-space workflows, while the host runtime
assignments in `modules/lib/r2-runtime.nix` (applied only when the host policy
enables the runtime) explicitly point to `/run/secrets/r2/credentials.env`.

## Quick Verification

```bash
rg -n 'path_regex: secrets/r2\\.yaml' modules/security/sops-policy.nix
rg -n 'r2/(account-id|access-key-id|secret-access-key|restic-password|explorer-admin-kid|explorer-admin-secret)' modules/security/r2-cloud-secrets.nix
rg -n 'templates\."(r2-credentials\.env|r2-explorer\.env|cloudflare/r2/env)"' modules/security/r2-cloud-secrets.nix modules/home/r2-secrets.nix
```
