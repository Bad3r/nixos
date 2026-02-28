# Troubleshooting

## Scope

Fast diagnosis for integration-specific failures between this repo and
`nix-R2-CloudFlare-Flake`.

## Source of Truth

- `flake.nix`
- `modules/system76/imports.nix`
- `modules/security/r2-cloud-secrets.nix`
- `modules/system76/r2-runtime.nix`
- `modules/home/r2-secrets.nix`

## Not Covered

- Duplicati-specific issues (`docs/usage/duplicati-r2-backups.md`)
- Producer-repo CI/workflow failures

## Symptom: Missing `r2` options during eval/build

Typical error shape:

- missing option/attribute under `services.r2-*`, `programs.git-annex-r2`, or
  `programs.r2-cloud`

Checks:

```bash
rg -n 'inputs\\.r2-flake\\.nixosModules\\.default' modules/system76/imports.nix
rg -n 'inputs\\.r2-flake\\.homeManagerModules\\.default' modules/system76/imports.nix
```

Fix:

- restore both import lines in `modules/system76/imports.nix`

## Symptom: `/run/secrets/r2/*` files missing at runtime

Checks:

```bash
test -f secrets/r2.yaml && echo present || echo missing
rg -n 'path_regex: secrets/r2\\.yaml' modules/security/sops-policy.nix
rg -n 'r2SecretExists|builtins\\.pathExists' modules/security/r2-cloud-secrets.nix
```

Fix:

1. ensure `secrets/r2.yaml` exists and is encrypted with a matching SOPS policy
2. confirm creation rule still includes `secrets/r2.yaml`
3. rebuild/activate after secret changes

## Symptom: `r2-mount-*` or `r2-restic-backup` fails to start

Checks:

```bash
systemctl status r2-mount-workspace --no-pager
systemctl status r2-restic-backup --no-pager
journalctl -u r2-mount-workspace -n 100 --no-pager
journalctl -u r2-restic-backup -n 100 --no-pager
```

Common causes:

- credentials/account/password file path missing under `/run/secrets/r2`
- permissions/ownership mismatch on `/data/r2/*` paths
- missing account ID in rendered credentials env

Fix:

- verify `modules/system76/r2-runtime.nix` paths match
  `modules/security/r2-cloud-secrets.nix` template outputs exactly
- verify tmpfiles directories are present and user-owned (`vx`)

## Symptom: `r2 share worker ...` fails due missing admin env vars

Checks:

```bash
test -s /run/secrets/r2/explorer.env
rg -n 'explorerEnvFile' modules/system76/r2-runtime.nix modules/security/r2-cloud-secrets.nix
```

Fix:

- ensure `explorer_admin_kid` and `explorer_admin_secret` are present in
  `secrets/r2.yaml`
- ensure `/run/secrets/r2/explorer.env` template is still declared and assigned
  to `programs.r2-cloud.explorerEnvFile`

## Symptom: HM env path confusion

Facts:

- system runtime uses `/run/secrets/r2/credentials.env`
- HM template module renders `~/.config/cloudflare/r2/env`

Fix:

- decide which surface should be used by each consumer and keep paths explicit
- do not rely on defaults when system-level runtime should use `/run/secrets/r2`
