# sops-nix Usage in This Repository

Secrets are managed with [sops](https://github.com/getsops/sops) and [sops-nix](https://github.com/Mic92/sops-nix).
The policy stays small: a single age host key that doubles as the editor key, plus templates that expose runtime files only when the encrypted material exists.

- [Adding a secret](adding-secrets.md): the YAML shape, the declaration, and how consumers read it.
- [CI evaluation](ci-evaluation.md): evaluating without the private submodule, and the `path:` copy hazard.
- [Troubleshooting](troubleshooting.md): error messages and their fixes.
- [GitHub token for act](secrets-act.md) and [R2 secrets](../r2-cloud/secrets-and-rendered-files.md): the two worked integrations.

## What Ships in the Repo

The `secrets/` content comes from a git submodule.
`flake.nix` sets `self.submodules = true`, so a consumer that fetches this repository as a flake input includes `secrets/` without adding `?submodules=1` to the input URL.
Direct local evaluation uses the checked-out worktree Nix was given, so the submodule stays initialized locally, or the repository is referenced with a Git flake URI that includes `?submodules=1`.
Either way, the `builtins.pathExists` guards evaluate against the real checkout content.

- `.sops.yaml` holds the policy, with one age recipient, `host_pub_key`, that both edits secrets and decrypts them at activation.
  The maintainer holds the matching private key in `~/.config/sops/age/keys.txt` (Home Manager) and `/var/lib/sops-nix/key.txt` (system).
- Its creation rules end in a deny-by-default rule covering every path under `secrets/`, and SOPS applies the first matching rule, so that rule stays last.
- `checks.<system>.secrets-no-cleartext` (`modules/security/sops-cleartext-check.nix`) is the evaluation-time gate for an initialized `secrets/` tree, failing on non-exempt cleartext and on drift in the policy contract.
  Plaintext lives under a `decrypted_*` name or a `*.dec.*` name, which the submodule's `.gitignore` hides and the check exempts.
- `modules/security/sops-runtime.nix` owns the shared NixOS sops-nix import and points `sops.age.keyFile` to `/var/lib/sops-nix/key.txt`; the `age` and `sops` CLIs come from their app rows.
- `modules/security/secrets.nix` only declares repository-managed system secrets and templates.
- Each secret declaration is guarded with `builtins.pathExists`, so a missing encrypted file, such as `secrets/act.yaml`, skips its block instead of failing evaluation.
- Secret files resolve from `${rootPath}/secrets` through the shared `secretsRoot` module argument, with no dedicated flake input.
- Templates write to stable paths, such as `/etc/act/secrets.env`, and take their ownership from `config.flake.lib.meta.owner.username`.

## Host Preparation

The repository uses one canonical age recipient, so preparing a host means installing the existing private identity that matches `host_pub_key`, not generating a per-host key.

1. Restore the canonical age identity from secure backup (root):

   ```bash
   sudo install -d -m 0700 -o root -g root /var/lib/sops-nix
   sudo install -m 0600 -o root -g root /path/to/secure-backup/key.txt /var/lib/sops-nix/key.txt
   sudo age-keygen -y /var/lib/sops-nix/key.txt
   ```

2. Confirm the printed public key matches `host_pub_key` in `.sops.yaml`.

3. Keep a secure offline copy of `/var/lib/sops-nix/key.txt`.

### Key Rotation

A replacement identity is generated only when rotating the canonical recipient.
Rotation updates the policy and re-encrypts every managed secret, so no file stays encrypted to the retired key.

1. Generate the replacement identity (root):

   ```bash
   sudo install -d -m 0700 -o root -g root /var/lib/sops-nix
   sudo age-keygen -o /var/lib/sops-nix/key.txt.next
   sudo chmod 0600 /var/lib/sops-nix/key.txt.next
   sudo age-keygen -y /var/lib/sops-nix/key.txt.next
   ```

2. Replace `host_pub_key` in `.sops.yaml` and the matching `hostPubKey` literal in `modules/security/sops-cleartext-check.nix` with the printed public key.

3. Run `sops updatekeys` for every encrypted file under `secrets/`.
   Until it finishes, `secrets-no-cleartext` reports the existing payloads as cleartext, because their metadata still names the retired recipient.

4. Deploy the updated configuration, install the replacement identity as `/var/lib/sops-nix/key.txt` on every host that decrypts these secrets, and store a secure offline backup.

### Home Manager user service

`modules/home-manager/sops-runtime.nix` runs the user `sops-nix.service` with an isolated home directory at `~/.local/share/sops-nix`, which never sees `~/.ssh/`, so hardware-backed SSH keys coexist with SOPS.
`~/.config/sops/age/keys.txt` must hold the user age identity matching the `host_pub_key` recipient.
A host provisioned with only the system key decrypts `/run/secrets/*` but cannot render Home Manager secrets such as `~/.config/cloudflare/r2/env`.

## Editing Encrypted Files Safely

### Interactive Editing

`sops` decrypts, opens the editor, and re-encrypts on save:

```bash
sops secrets/<name>.yaml
```

### URL Catalog Helper

`scripts/url-catalog-add.py` interactively appends URL records to the catalog schema that `secrets/decrypted_url_catalog.yaml` uses.
It is a `uv` script with inline dependency metadata for `ruamel.yaml`, so it runs through `uv` rather than `python`.
It accepts full URLs and bare domains, such as `example.org` or `service-name.onion`, and writes catalog metadata only; SOPS encrypts the whole catalog file.

Edit the ignored plaintext template:

```bash
uv run --script scripts/url-catalog-add.py
```

Edit an encrypted catalog through SOPS:

```bash
EDITOR='uv run --script scripts/url-catalog-add.py' sops secrets/url-catalog.yaml
```

The helper refuses direct edits to an already encrypted file, and asks before writing plaintext to a non-`decrypted_` path under `secrets/`.

### Programmatic / Scripted Editing

A script that modifies a secret decrypts to a temporary file, edits it, copies it to the target path, and encrypts in place:

```bash
sops -d secrets/<name>.yaml > /tmp/plain.yaml && \
  # modify /tmp/plain.yaml as needed, then:
  cp /tmp/plain.yaml secrets/<name>.yaml && \
  sops -e -i secrets/<name>.yaml && \
  rm /tmp/plain.yaml
```

The final encryption step is always `sops -e -i`, never a shell redirect:

- `sops -e /tmp/file.yaml > secrets/original.yaml`: the shell truncates `original.yaml` to 0 bytes before sops runs, so a failing sops loses the original.
- `sops -d secrets/file.yaml > secrets/file.yaml`: the same truncation destroys the input before sops reads it.
- `sops -e secrets/file.tmp > secrets/file.yaml`: the deny-by-default rule matches `.tmp`, but the plaintext source stays under `secrets/`, where the cleartext gate rejects it.
- `sops -e -i secrets/file.yaml.example`: the deny-by-default rule also matches `*.example`, so SOPS encrypts a template that the cleartext gate rejects as accidental template encryption; `*.example` files are edited directly.
