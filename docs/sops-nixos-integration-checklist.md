# SOPS‑nix Integration Checklist (NixOS, Home‑Manager, CI, act)

This checklist is an actionable plan to implement the patterns described in `docs/sops-nixos.md`. It drives a secure, minimal‑friction integration of sops‑nix across NixOS, Home‑Manager, CI, and local `act` runs.

## Execution Order and Verification

- [x] Phase 0 — Prerequisites
  - [x] Nix flakes enabled; repo builds and evaluates.
  - [x] `sops` and `age` available locally (via devshell or system).
- [ ] Phase 1 — Governance + Keys
  - [ ] Create `.sops.yaml` with recipients (your admin key + host keys), readable diffs configured.
  - [ ] Provision host Age key(s); add pubkeys to `.sops.yaml`; back up key files.
  - [ ] Verify: `sops -e` works and diffs are readable; `sops -d` succeeds using `SOPS_AGE_KEY_FILE`.
- [x] Phase 2 — Wire sops‑nix
  - [x] Import `sops-nix` module(s); set `sops.age.keyFile`; choose default vs per‑secret.
  - [x] Verify: `nix flake check --accept-flake-config` evaluates.
- [ ] Phase 3 — First Secret + Template
  - [ ] Encrypt a secret file; declare `sops.secrets` and (optionally) `sops.templates`; expose a stable path.
  - [ ] Verify: configuration evaluates; secret references use `.path`/templates (no eval‑time reads).
- [ ] Phase 4 — Home‑Manager
  - [ ] Import HM sops module; set user key; declare at least one user secret; order services after `sops-nix.service`.
- [ ] Phase 5 — Dev Tooling + Hooks + Git Credentials
  - [ ] Install pre‑commit hooks; configure sops‑diff; set up Git credential helper per URL.
  - [ ] Verify: hook rejects plaintext in secret paths; `git ls-remote` works using helper.
- [ ] Phase 6 — CI + act
  - [ ] Configure Nix fetcher auth; create `secrets/act.yaml`; render `/etc/act/secrets.env`.
  - [ ] Verify: `grep -q '^GITHUB_TOKEN=' /etc/act/secrets.env`; run `act -n` with `--secret-file`.
- [ ] Phase 7 — Optional: Kubernetes/Helm
  - [ ] Configure KSOPS + Helm‑secrets where applicable; verify kustomize build.
- [ ] Phase 8 — Rotation + Decommissioning
  - [ ] Rotate recipients/data keys and verify; decommission hosts and revoke tokens.
- [ ] Phase 9 — Final Validation
  - [ ] `nix fmt`, `pre-commit run --all-files`, `generation-manager score`, and `nix flake check` all pass.

## Governance: `.sops.yaml` and Recipients

Cross‑reference: See `docs/sops-nixos.md` → Introduction, Key Management, Reference (Core Options).

- [ ] Decide on crypto: prefer Age; use GPG only if required.
- [ ] Add admin keys (Age pubkeys or GPG fingerprints) under `keys:` anchors.
- [ ] Add host Age recipients for each NixOS machine.
- [ ] Add targeted rules (e.g., `secrets/act.yaml` with `encrypted_regex: ^(github_token)$`).
- [ ] Avoid unintended Shamir semantics: keep `key_groups` properly nested, do not add stray `-`.
  - Clarification: Shamir secret sharing requires multiple keys to decrypt. Incorrect YAML structure can accidentally enable this, making secrets inaccessible with a single key. Ensure `age`/`pgp` lists are nested under `key_groups` without extraneous dashes.
- [ ] Configure readable diffs:
  - [x] Add `.gitattributes`: `*.yaml diff=sopsdiffer`
  - [ ] `git config diff.sopsdiffer.textconv "sops decrypt"`
- [ ] Write personal rotation notes (where your keys are backed up, how to recover).

## Host Age Key Provisioning

Cross‑reference: See `docs/sops-nixos.md` → Key Management (Age vs GPG, Key Generation Strategies).

- [ ] On each host, create `/var/lib/sops-nix/key.txt` (0600; owner root):
  - [ ] `sudo install -d -m 0700 -o root -g root /var/lib/sops-nix`
  - [ ] `sudo age-keygen -o /var/lib/sops-nix/key.txt`
  - [ ] `sudo chmod 0600 /var/lib/sops-nix/key.txt`
- [ ] Capture and add public key to `.sops.yaml` recipients:
  - [ ] `sudo grep -E '^# public key:' /var/lib/sops-nix/key.txt | sed 's/^# public key: //'`
- [ ] Back up `/var/lib/sops-nix/key.txt` (host‑local secure backup).
- [ ] Optional: enable `sops.age.generateKey = true;` if operationally acceptable.

## NixOS: Wire sops‑nix in Base

Cross‑reference: See `docs/sops-nixos.md` → Installation and Setup, Reference (Core/Age Options).

- [x] Import module: `inputs.sops-nix.nixosModules.sops`.
- [x] Set `sops.age.keyFile = "/var/lib/sops-nix/key.txt";` (and `generateKey` if desired).
- [x] Ensure `sops` and `age` are available (systemPackages or via devshell for ops).
- [x] Avoid `sops.defaultSopsFile` for production (keeps encrypted files out of the store).

## NixOS: Declare Secrets Securely

Cross‑reference: See `docs/sops-nixos.md` → Basic Usage (Declaring), Advanced Patterns (Templates), Quick Reference.

- [ ] For each secret, declare with per‑secret `sopsFile` and strict perms:
  - [ ] `mode = "0400";`
  - [ ] `owner = config.users.users.<svcUser>.name;`
  - [ ] `group = config.users.users.<svcUser>.group;` (when needed)
- [ ] In services, reference `config.sops.secrets.<name>.path`.
- [x] Do not rely on `/run/secrets.d/N` directly (N increments at each activation).
- [x] NEVER read secrets at evaluation time (avoid `builtins.readFile` on secret paths). Read at runtime via `.path` or templates.
- [ ] If a secret must be available before user creation, set `sops.secrets.<name>.neededForUsers = true;` and ensure it is root‑owned.
- [ ] If referencing sops files from the Nix store, consider `sops.validateSopsFiles = true;`. If using absolute `sopsFile` paths outside the store, set it to `false` or accept the tradeoff.

## NixOS: Templates and Stable Paths

Cross‑reference: See `docs/sops-nixos.md` → Advanced Patterns (Templates), Quick Reference (Stable paths, perms).

- [x] Use `sops.templates` + placeholders to render config files with secrets.
- [x] Expose stable paths with `environment.etc."<name>".source = config.sops.templates."<tmpl>".path;`.
- [x] Verify rendered files have correct `owner`/`group`/`mode` and are only read by the intended service/user.
- [ ] Order system services that consume secrets: `systemd.services.<name>.unitConfig = { After = [ "sops-nix.service" ]; Wants = [ "sops-nix.service" ]; };`
- [ ] When secrets or templates change, trigger updates: use `restartUnits` or `reloadUnits` on the relevant `sops.secrets`/`sops.templates` entries.
- [ ] Note: `/run/secrets.d/<N>` is owned by root with group `keys` and restrictive traversal; ensure owner/group/mode allow the target service to read the secret.

## Home‑Manager Integration

Cross‑reference: See `docs/sops-nixos.md` → Home‑Manager Integration, Quick Reference (Ordering).

- [ ] Import `inputs.sops-nix.homeManagerModules.sops`.
- [x] Set user key: `sops.age.keyFile = "/home/<user>/.age-key.txt";` (no passphrase).
- [ ] Use `%r` for runtime paths; optionally set `defaultSopsFile`.
- [ ] Order dependent user services: `systemd.user.services.<name>.unitConfig.After = [ "sops-nix.service" ];` and optionally `Wants = [ "sops-nix.service" ];`.
- [ ] Generate a developer Age key if needed:
  - [ ] `mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt`
  - [ ] Or convert SSH key: `ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt`
  - [ ] Back up the key securely (e.g., encrypted removable media).

## Dev Tooling and Onboarding

Cross‑reference: See `docs/sops-nixos.md` → Tools and Utilities, Quick Reference (Git credential helper).

- [x] Ensure devshell includes: `sops`, `age`, `ssh-to-age`, `ssh-to-pgp`, `act`, and helper scripts.
- [ ] Add a short personal note for generating your Age key and adding it as a recipient.
- [ ] Provide commands to list and dry‑run GitHub Actions locally.
- [ ] Configure a Git credential helper that reads a sops‑managed token at runtime and scope it per URL:
  - [ ] `git config --global credential.useHttpPath true`
  - [ ] `git config --global 'credential.https://github.com.helper' '!/path/to/git-credential-sops'`

## Pre‑Commit and Repo Hygiene

Cross‑reference: See `docs/sops-nixos.md` → Security Best Practices, Quick Reference (Validation).

- [x] Add `pre-commit-hook-ensure-sops` to enforce encryption on matching paths.
- [ ] Run `pre-commit install` locally; ensure CI runs `pre-commit run --all-files`.
- [ ] Ensure `.sops.yaml` governs all paths where secrets appear.
- [ ] Verify hooks work: attempt to commit a plaintext file within a secret path and confirm the hook rejects the commit.

## CI Authentication and Safety

Cross‑reference: See `docs/sops-nixos.md` → CI/CD Integration, Quick Reference.

- [ ] Use HTTPS remotes instead of SSH for GitHub.
- [ ] Configure Nix fetcher auth: `access-tokens = github.com=${{ secrets.GITHUB_TOKEN }}` in `nix.conf` (CI).
- [ ] Avoid secrets at evaluation time; decrypt only at activation/runtime as needed.
- [ ] Pin Nix version in containers if required (e.g., `2.30.x` to match features used).
- [ ] Configure a Git credential helper for CI environments if tokens are required at runtime (see Dev Tooling section).

## Local `act` Integration

Cross‑reference: See `docs/sops-nixos.md` → CI/CD Integration (GitHub Actions with act), Quick Reference.

- [x] Add `.sops.yaml` rule for `secrets/act.yaml` (`github_token` field).
- [ ] Create/rotate token with `sops secrets/act.yaml`.
- [x] Render `GITHUB_TOKEN` via `sops.templates."act-env"`.
- [x] Publish stable path: `/etc/act/secrets.env` (0400; set owner to the user/service that runs `act`).
- [ ] List jobs: `act -l`
- [ ] Dry run: `act -n --secret-file /etc/act/secrets.env`
- [ ] Run job: `act -j <job> --secret-file /etc/act/secrets.env`
- [ ] Verify without leaking: `grep -q '^GITHUB_TOKEN=' /etc/act/secrets.env`.
- [ ] Do not echo or print token values in logs; use presence/format checks instead.

## Optional: Kubernetes Tooling

Cross‑reference: See `docs/sops-nixos.md` → Kubernetes Integration (KSOPS), Tools and Utilities.

- [ ] KSOPS (`kustomize-sops`): set `KUSTOMIZE_PLUGIN_HOME` to the package `lib` path; use `--enable-alpha-plugins --load-restrictor LoadRestrictionsNone`.
- [ ] Helm: expose `helm-secrets` via `HELM_PLUGINS` and ensure `sops` in PATH.

## Rotation, Backup, and Migration

Cross‑reference: See `docs/sops-nixos.md` → Key Management (Key Rotation), Migration Strategies, Quick Reference.

- [ ] Define rotation cadence and playbook (tokens/passwords/keys).
- [ ] Use `sops updatekeys` after recipient changes.
- [ ] Revoke/rotate GitHub PATs promptly; update `secrets/*.yaml` accordingly.
- [ ] Back up host keys; document recovery if a host key is lost (re‑provision + update recipients).
- [ ] Rotate data keys periodically: `sops -r <file>`; re‑encrypt and verify via `sops -d`.
- [ ] Decommissioning: remove host recipients from `.sops.yaml` and run `sops updatekeys`; revoke tokens/credentials; securely wipe `/var/lib/sops-nix/key.txt` and backups; verify removed recipients can no longer decrypt.

## Validation (Non‑Destructive)

Cross‑reference: See `docs/sops-nixos.md` → Quick Reference (Validation), Security Best Practices.

- [ ] `nix fmt`
- [ ] `nix develop -c pre-commit run --all-files`
- [ ] `generation-manager score` (target: 90/90)
- [ ] `nix flake check --accept-flake-config`
- [ ] Never run build/switch/GC in validation.

---

Acceptance criteria:

- [ ] Secrets never appear in plaintext in the store; all services consume via `.path` or stable `environment.etc`.
- [ ] All secret files and templates use least‑privilege `owner`/`group`/`mode`.
- [ ] HM services order correctly after `sops-nix.service`.
- [ ] CI fetches authenticated via access‑tokens; no eval‑time secrets.
- [ ] Local `act` uses `/etc/act/secrets.env` with non‑leaky verification.
- [ ] Pre‑commit blocks unencrypted secrets; git diffs of encrypted files are readable.
