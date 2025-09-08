# Next Steps: sops-nix + age + act/CI

For a full, repo-scoped guide to using SOPS on NixOS (keys, .sops.yaml, secrets declaration, templates, Home‑Manager, CI, KSOPS, hooks, troubleshooting), see docs/sops-nixos.md.

This is a temporary checklist to finish wiring encrypted secrets for running GitHub Actions locally with `act`, and to ensure CI auth works cleanly without SSH keys.

Status summary (implemented)

- sops-nix integrated: `inputs.sops-nix` added; module imported via `modules/security/secrets.nix`.
- Secret plumbing: if `secrets/act.yaml` exists, NixOS renders `/etc/act/secrets.env` with `GITHUB_TOKEN=...` (0400, owned by `vx`).
- Dev shell: `gh-actions-run` auto-adds `--secret-file /etc/act/secrets.env` when present; override with `ACT_SECRETS_FILE=/path`.
- CI workflow: Uses Nix 2.30.2; rewrites SSH→HTTPS; configures Nix `access-tokens = github.com=${{ secrets.GITHUB_TOKEN }}`.
- Runner image: `ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-24.04` (medium image).

What you need to do

1. Add your age recipients to `.sops.yaml`

- File: `.sops.yaml` (already created) contains a rule for `secrets/act.yaml`.
- Add your public keys under `age:` (replace placeholders):

```yaml
creation_rules:
  - path_regex: secrets/act.yaml
    encrypted_regex: "^(github_token)$"
    age:
      - age1.........................................................
      - age1.........................................................
```

2. Generate host age key (if not already present)

- On each machine that should decrypt secrets:

```bash
sudo install -d -m 0700 -o root -g root /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 0600 /var/lib/sops-nix/key.txt
# Print public key to add into .sops.yaml
sudo grep -E '^# public key: ' /var/lib/sops-nix/key.txt | sed 's/^# public key: //'
```

3. Create a fine‑grained GitHub PAT (minimal scope)

- Scope: “Contents: read” only. Restrict to the repo/org as needed.
- Copy the token value; you’ll encrypt it in the next step.

4. Encrypt the token into `secrets/act.yaml`

- Requires your `.sops.yaml` to include at least one valid age recipient.
- First-time create:

```bash
sops --input-type yaml --output-type yaml \
  --set 'github_token <YOUR_PAT>' secrets/act.yaml
```

- To rotate/edit later:

```bash
sops secrets/act.yaml
```

- Commit the encrypted file (`secrets/act.yaml`), NOT the plaintext.

5. Apply on your NixOS host

- On the host that uses this repo configuration, rebuild/switch so sops-nix renders the template:

```bash
# Run your normal switch method (example)
sudo nixos-rebuild switch --flake .#<host>
```

- Verify the rendered env file:

```bash
ls -l /etc/act/secrets.env
# Expect: -r-------- vx vx /etc/act/secrets.env
# Verify format without printing the token value
grep -q '^GITHUB_TOKEN=' /etc/act/secrets.env
```

6. Run act locally with secrets

- Dry run all jobs:

```bash
nix develop -c gh-actions-run -n
```

- Full run (Docker required):

```bash
nix develop -c gh-actions-run
```

- Override secrets location if needed:

```bash
ACT_SECRETS_FILE=/path/to/env nix develop -c gh-actions-run -n
```

7. Ensure CI is ready

- Nothing extra needed — GitHub Actions provides `GITHUB_TOKEN` automatically.
- CI is configured to:
  - Prefer HTTPS for GitHub remotes to avoid SSH.
  - Install Nix 2.30.2.
  - Use `access-tokens = github.com=${{ secrets.GITHUB_TOKEN }}` so Nix fetchers authenticate.

8. Push input branches (input-branches pattern)

- Make sure refs like `inputs/main/home-manager`, `inputs/main/nixpkgs`, `inputs/main/stylix` are pushed, otherwise fetchers can’t find the referenced commits:

```bash
git push origin inputs/main/home-manager inputs/main/nixpkgs inputs/main/stylix
```

Rotation & revocation

- Rotate: `sops secrets/act.yaml` (update `github_token`), commit, switch host.
- Revoke: invalidate the PAT in GitHub settings; update the encrypted secret.
- Backup: store `/var/lib/sops-nix/key.txt` securely; losing it prevents decryption on that host.

Troubleshooting

- SSH publickey errors in act:
  - Fixed by HTTPS rewrite in CI; locally, `gh-actions-run` uses token via `--secret-file`.
- “unexpected flake input attribute 'submodules'”:
  - Resolved by installing modern Nix in the container (2.30.2 in CI).
- KVM/udevadm messages:
  - Safe to ignore in the container environment.
- Relative path warning: `path:./inputs/nixpkgs`:
  - Harmless notice during evaluation in this environment.

Security notes

- Never put tokens in Nix strings (they’d end up in the store).
- `/etc/act/secrets.env` is rendered at switch-time with 0400 perms, owned by `vx`.
- Use minimal PAT scopes; prefer org-level fine-grained tokens.

Reference commands

- List jobs: `nix develop -c gh-actions-list`
- Dry-run job: `nix develop -c gh-actions-run -n -j format-check`
- Full-run job: `nix develop -c gh-actions-run -j format-check`

Open items (you)

- [ ] Add your age public keys to `.sops.yaml`.
- [ ] Generate host age key(s) and paste their pubkeys into `.sops.yaml`.
- [ ] Create `secrets/act.yaml` with your PAT encrypted by sops and commit it.
- [ ] Switch your NixOS host to materialize `/etc/act/secrets.env`.
- [ ] Push input branches if not already pushed.

After completing the above, re-run:

- `nix develop -c gh-actions-run -n` (dry) and then `nix develop -c gh-actions-run` (full) to verify.
