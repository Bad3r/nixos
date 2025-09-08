Act Secrets via sops-nix (age)

Overview

- Manage a fine-grained GitHub PAT (Contents: read) using sops-nix.
- Decrypt at activation time only; never store secrets in the Nix store.
- Expose an env file `/etc/act/secrets.env` consumed by `act` locally.

Prereqs

- age key on host: `/var/lib/sops-nix/key.txt` (root-only).
- sops installed (provided via `modules/security/secrets.nix`).

Setup Steps

1. Generate age key (host):
   sudo install -d -m 0700 -o root -g root /var/lib/sops-nix
   sudo age-keygen -o /var/lib/sops-nix/key.txt
   sudo chmod 0600 /var/lib/sops-nix/key.txt

   # Show public key (starts with age1...)

   sudo grep -E "^# public key: " /var/lib/sops-nix/key.txt | sed 's/^# public key: //'

2. Add public key(s) to `.sops.yaml`:
   - Edit `.sops.yaml` and insert your `age1...` in the `age:` array for `secrets/act.yaml`.

3. Create/rotate the PAT (fine-grained, Contents: read) and encrypt it:

   # First-time create the encrypted file

   sops --input-type yaml --output-type yaml \
    --set 'github_token <YOUR_PAT>' secrets/act.yaml

   # To edit later

   sops secrets/act.yaml

4. Switch your system to apply sops-nix (creates the template):
   - Ensure the NixOS host imports this repo and `modules/security/secrets.nix` (auto-imported).
   - On switch, sops-nix decrypts and renders `/etc/act/secrets.env` with 0400 perms.

Usage with act

- Dev shell provides `gh-actions-run`. It auto-detects:
  - If `/etc/act/secrets.env` exists, it adds: `--secret-file /etc/act/secrets.env`.
  - Override with `ACT_SECRETS_FILE=/path/to/env` if needed.

CI notes

- CI uses the built-in `GITHUB_TOKEN` and configures Nix fetchers via:
  access-tokens = github.com=${{ secrets.GITHUB_TOKEN }}
- Workflows also rewrite SSH → HTTPS to avoid SSH keys entirely.

Security

- Never store tokens in Nix strings (would enter the store).
- Ensure `/var/lib/sops-nix/key.txt` is root-only (0600) and backed up securely.
- Rotate PAT regularly; `sops secrets/act.yaml` and re-switch.
