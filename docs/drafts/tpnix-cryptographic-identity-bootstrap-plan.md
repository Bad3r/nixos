# tpnix Cryptographic Identity Bootstrap Plan

Status: draft  
Host: `tpnix`  
Owner user: `vx`  
Scope: configure host-specific OpenPGP commit signing, SSH auth for GitHub, and SOPS host key provisioning.

## 1. Goal

Provide an end-to-end, reproducible, and host-isolated cryptographic setup for `tpnix` that:

1. Fixes Git commit signing failures on `tpnix`.
2. Enables GitHub push/auth over SSH on `tpnix`.
3. Enables `sops-nix` decryption on `tpnix` with a dedicated host Age key.
4. Keeps `tpnix` keys different from `system76` keys.

## 2. Final State (Acceptance Definition)

`tpnix` is considered complete only when all are true:

1. `git commit -S` succeeds and uses the `tpnix` OpenPGP fingerprint.
2. `ssh -T git@github.com` succeeds using a `tpnix`-specific SSH key.
3. `/var/lib/sops-nix/key.txt` exists on `tpnix` with `0600` and root ownership.
4. `sops-install-secrets` completes successfully on `tpnix`.
5. Host-specific secret files decrypt on `tpnix` and do not require `system76` host key.
6. `system76` keeps its own existing cryptographic identity and behavior.

## 3. Locked Decisions

1. Commit signing format: OpenPGP.
2. Private key management model: SOPS-managed.
3. Git signing key configuration ownership:
   - Shared defaults in `modules/git/git.nix`.
   - Host-specific fingerprint override in `modules/system76/imports.nix` and `modules/tpnix/imports.nix`.
4. Secret file layout:
   - `secrets/gpg/system76.asc`
   - `secrets/gpg/tpnix.asc`
   - `secrets/ssh/tpnix/id_ed25519.asc`
5. Runtime secret paths:
   - Home Manager `config.sops.secrets."gpg/vx-secret-key".path` (declared via a dedicated Home Manager GPG secret module)
   - `/run/secrets/ssh/vx-auth-key` (declared via `sops.secrets."ssh/vx-auth-key"`)
6. SSH client identity for `tpnix`: use managed runtime key path, not `~/.ssh/id_ed25519`.

## 4. Security Standards Applied

1. Host key separation: no shared signing/auth private keys across hosts.
2. Secret-at-rest encryption: all private key material in repository is SOPS-encrypted.
3. Runtime-only secret consumption: keys accessed only through `sops.secrets.*.path`.
4. Deterministic configuration: no range placeholders, no ambiguous defaults in plan steps.
5. Least privilege permissions:
   - `/var/lib/sops-nix/key.txt`: `0600 root:root`
   - SSH private runtime key: `0400 vx:<primary-group>`
6. No plaintext key persistence:
   - Temporary plaintext export files are removed immediately after encryption/import.

## 5. Implementation Changes (Decision Complete)

## 5.1 Module Changes

1. `modules/git/git.nix`
   - Keep:
     - `signing.signByDefault = true`
     - `signing.format = "openpgp"`
   - Remove hard-coded shared `signing.key`.

2. `modules/system76/imports.nix`
   - Add explicit host signing key:
     - `home-manager.users.${metaOwner.username}.programs.git.signing.key = lib.mkForce "<SYSTEM76_GPG_FINGERPRINT>";`

3. `modules/tpnix/imports.nix`
   - Do not rely on `security.repoSecrets` for OpenPGP material; that module is ACT-only.
   - Add explicit host signing key:
     - `home-manager.users.${metaOwner.username}.programs.git.signing.key = lib.mkForce "<TPNIX_GPG_FINGERPRINT>";`
   - Override SSH identity file for `tpnix`:
     - `home-manager.users.${metaOwner.username}.programs.ssh.matchBlocks."*".identityFile = lib.mkForce [ "/run/secrets/ssh/vx-auth-key" ];`

4. `modules/security/secrets.nix`
   - Resolve host slug from `config.networking.hostName`.
   - Add host-scoped SSH secret source:
     - `secrets/ssh/${host}/id_ed25519.asc`
   - Keep repository ACT secrets separate from host key material.
   - Declare:
     - `sops.secrets."ssh/vx-auth-key"` (`format = "binary"`, owner `vx`, mode `0400`, path `/run/secrets/ssh/vx-auth-key`)

5. `modules/home/pass-secret-service.nix`
   - Replace static fingerprint with dynamic source:
     - `config.programs.git.signing.key`
   - Read secret path from Home Manager config:
     - `config.sops.secrets."gpg/vx-secret-key".path`
   - Keep guarded activation (import only when both fingerprint and secret path exist).

6. `modules/tpnix/ssh.nix`
   - Set actual `tpnix` host SSH public key:
     - `services.openssh.publicKey = "ssh-ed25519 ... root@tpnix";`
   - Keep hardening:
     - `PasswordAuthentication = false`
     - `PermitRootLogin = "no"`

7. `modules/security/sops-policy.nix`
   - Expand recipients to include:
     - owner/editor key
     - `system76` host key
     - `tpnix` host key
   - Add explicit path rules for host-separated GPG/SSH files.
   - Keep existing service secret rules (`act`, `r2`, `fonts`) intact unless explicitly changed.

## 5.2 Secret Inventory Changes

1. Existing `secrets/gpg/vx.asc` is split into host-specific files.
2. Add:
   - `secrets/gpg/system76.asc`
   - `secrets/gpg/tpnix.asc`
   - `secrets/ssh/tpnix/id_ed25519.asc`

## 6. Key Provisioning Runbook (Fresh Host)

## 6.1 SOPS Host Age Key (Mandatory)

1. Create storage directory:
   - `sudo install -d -m 0700 -o root -g root /var/lib/sops-nix`
2. Generate key:
   - `sudo age-keygen -o /var/lib/sops-nix/key.txt`
3. Set strict permissions:
   - `sudo chmod 0600 /var/lib/sops-nix/key.txt`
4. Verify:
   - `sudo test -r /var/lib/sops-nix/key.txt`
   - `sudo age-keygen -y /var/lib/sops-nix/key.txt`
5. Add printed recipient to `modules/security/sops-policy.nix`.

## 6.2 OpenPGP Key for Git Signing

1. Generate key:
   - `gpg --full-generate-key`
2. Extract long fingerprint:
   - `gpg --list-secret-keys --keyid-format=long`
3. Export public key:
   - `gpg --armor --export <TPNIX_GPG_KEYID> > /tmp/tpnix-gpg-public.asc`
4. Export private key for SOPS ingestion:
   - `gpg --armor --export-secret-keys <TPNIX_GPG_KEYID> > /tmp/tpnix-gpg-private.asc`
   - `chmod 0600 /tmp/tpnix-gpg-private.asc`
5. Register public key in GitHub:
   - `gh gpg-key add /tmp/tpnix-gpg-public.asc -t "tpnix-openpgp"`

## 6.3 SSH Authentication Key for GitHub

1. Generate SSH key:
   - `ssh-keygen -t ed25519 -a 100 -C "25513724+Bad3r@users.noreply.github.com (tpnix)" -f /tmp/tpnix-id_ed25519`
2. Set file permissions:
   - `chmod 0600 /tmp/tpnix-id_ed25519`
   - `chmod 0644 /tmp/tpnix-id_ed25519.pub`
3. Start agent and load key:
   - `eval "$(ssh-agent -s)"`
   - `ssh-add /tmp/tpnix-id_ed25519`
4. Register key in GitHub:
   - `gh ssh-key add /tmp/tpnix-id_ed25519.pub --type authentication --title "tpnix-auth"`

## 6.4 Capture Host SSH Public Key

1. Read host key:
   - `sudo cat /etc/ssh/ssh_host_ed25519_key.pub`
2. Place exact value into `modules/tpnix/ssh.nix` as `services.openssh.publicKey`.

## 7. SOPS Encryption and Re-Key Workflow

1. Regenerate generated policy file:
   - `nix develop -c write-files`
2. One-time migration for current `system76` GPG file (required in current repo state):
   - `test -f secrets/gpg/vx.asc && cp secrets/gpg/vx.asc secrets/gpg/system76.asc`
   - Keep `secrets/gpg/vx.asc` until `system76` validation is complete, then remove legacy file in a follow-up cleanup with `rip secrets/gpg/vx.asc`.
3. Create encrypted host-specific files:
   - `cp /tmp/tpnix-gpg-private.asc secrets/gpg/tpnix.asc`
   - `sops -e -i secrets/gpg/tpnix.asc`
   - `install -d -m 0755 secrets/ssh/tpnix`
   - `cp /tmp/tpnix-id_ed25519 secrets/ssh/tpnix/id_ed25519.asc`
   - `sops -e -i secrets/ssh/tpnix/id_ed25519.asc`
4. Re-key after policy updates:
   - `sops updatekeys secrets/gpg/system76.asc`
   - `sops updatekeys secrets/gpg/tpnix.asc`
   - `sops updatekeys secrets/ssh/tpnix/id_ed25519.asc`
5. Remove plaintext temp files:
   - `shred -u /tmp/tpnix-gpg-public.asc /tmp/tpnix-gpg-private.asc /tmp/tpnix-id_ed25519 /tmp/tpnix-id_ed25519.pub`

## 8. Validation Gates

## 8.1 Config/Eval Validation

1. Validate host signing key:
   - `nix eval --accept-flake-config --raw .#nixosConfigurations.tpnix.config.home-manager.users.vx.programs.git.signing.key`
2. Validate declared secrets:
   - `nix eval --accept-flake-config --json .#nixosConfigurations.tpnix.config.sops.secrets --apply builtins.attrNames`
3. Validate SSH identity file path:
   - `nix eval --accept-flake-config --raw .#nixosConfigurations.tpnix.config.home-manager.users.vx.programs.ssh.matchBlocks."*".identityFile.0`
4. Validate host key publication:
   - `nix eval --accept-flake-config .#nixosConfigurations.tpnix.config.services.openssh.publicKey`

## 8.2 Build Validation

1. `nix flake check --accept-flake-config --no-build --offline`
2. `nix build .#nixosConfigurations.tpnix.config.system.build.toplevel`

## 8.3 Runtime Validation on tpnix

1. `gpg --list-secret-keys --keyid-format=long`
2. `git config --global --get user.signingkey`
3. `git commit --allow-empty -S -m "test(tpnix): signing verification"`
4. `ssh -T git@github.com`
5. `git push --dry-run`
6. `systemctl status sops-install-secrets.service`
7. `journalctl -u sops-install-secrets -b --no-pager`

## 9. Rollback Plan

1. Revert only touched files:
   - `modules/git/git.nix`
   - `modules/system76/imports.nix`
   - `modules/tpnix/imports.nix`
   - `modules/security/secrets.nix`
   - `modules/home/pass-secret-service.nix`
   - `modules/tpnix/ssh.nix`
   - `modules/security/sops-policy.nix`
2. Remove newly registered GitHub keys by title if rollout is abandoned.
3. Restore previous encrypted secret files if host-scoped split is rolled back.
4. Re-run `nix develop -c write-files` after rollback to resync generated policy.

## 10. Primary Sources

1. GitHub Docs: Generating a new GPG key  
   https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key
2. GitHub Docs: Adding a GPG key to your GitHub account  
   https://docs.github.com/en/authentication/managing-commit-signature-verification/adding-a-gpg-key-to-your-github-account
3. GitHub Docs: Telling Git about your signing key  
   https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key
4. GitHub Docs: Generating a new SSH key and adding it to the ssh-agent  
   https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
5. GitHub Docs: Adding a new SSH key to your GitHub account  
   https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account
6. GitHub CLI: `gh gpg-key add`  
   https://cli.github.com/manual/gh_gpg-key_add
7. GitHub CLI: `gh ssh-key add`  
   https://cli.github.com/manual/gh_ssh-key_add
8. Git upstream config docs  
   https://raw.githubusercontent.com/git/git/master/Documentation/config/gpg.adoc  
   https://raw.githubusercontent.com/git/git/master/Documentation/config/user.adoc  
   https://raw.githubusercontent.com/git/git/master/Documentation/config/commit.adoc  
   https://raw.githubusercontent.com/git/git/master/Documentation/config/tag.adoc
9. NixOS module sources  
   https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/programs/gnupg.nix  
   https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/services/networking/ssh/sshd.nix  
   https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/programs/ssh.nix
10. Local docs  
    `docs/sops/README.md`  
    `docs/index.md`  
    `nixos-manual/configuration/ssh.section.md`
