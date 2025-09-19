# GitHub Token for `act` via sops-nix

This repository stores the personal access token used by `act` in `secrets/act.yaml` and renders `/etc/act/secrets.env` at activation time. The integration lives in `modules/security/secrets.nix` and follows the general guidance in `docs/sops-nixos.md`.

## Overview

- The `.sops.yaml` policy (generated from `modules/security/sops-policy.nix`) already targets `secrets/act.yaml` and encrypts only the `github_token` field.
- `modules/security/secrets.nix` declares `sops.secrets."act/github_token"` and a template `sops.templates."act-env"` that becomes `/etc/act/secrets.env`.
- The development shell command `gh-actions-run` automatically passes `--secret-file /etc/act/secrets.env` when the file exists. Override the path with `ACT_SECRETS_FILE=/path/to/env`.

## Host Setup (one-time)

1. Generate the Age host key if it does not already exist (see `docs/sops-nixos.md`).
2. Ensure the host key is listed in `modules/security/sops-policy.nix` (it is named `host_primary` by default). Run `nix develop -c write-files` to refresh `.sops.yaml`.

## Adding or Rotating the Token

```bash
# Edit (or create) the encrypted file
sops secrets/act.yaml

# Inside the editor, set the field
# github_token: ghp_...
```

After committing the encrypted file, switch the host:

```bash
sudo nixos-rebuild switch --flake .#system76
```

`sops-nix` decrypts the secret during activation and writes `/etc/act/secrets.env` with permissions `0400` and owner `${config.flake.lib.meta.owner.username}`.

To verify locally (without printing the token):

```bash
sudo test -f /etc/act/secrets.env
sudo grep -q '^GITHUB_TOKEN=' /etc/act/secrets.env
```

## Using the Token with `act`

Run GitHub Actions locally:

```bash
nix develop -c gh-actions-run -n     # dry run to verify configuration
nix develop -c gh-actions-run        # full run (requires Docker)
```

Pass a different secret file if needed:

```bash
ACT_SECRETS_FILE=$PWD/tmp/secrets.env nix develop -c gh-actions-run
```

## Security Notes

- Secrets never enter the Nix store; they are decrypted at activation only.
- `/etc/act/secrets.env` is owned by the repo owner user and has permissions `0400`.
- Rotate PATs regularly and revoke unused tokens in GitHub.
- Keep `/var/lib/sops-nix/key.txt` backed up securely; losing it prevents the host from decrypting secrets until you rotate the policy.
