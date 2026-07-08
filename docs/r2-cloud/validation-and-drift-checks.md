# Validation and Drift Checks

## Scope

Operator checks to confirm `r2-flake` integration is intact and still mapped to
expected files/options in this repository.

## Source of Truth

- `flake.nix`
- `modules/lib/r2-runtime.nix`
- per-host `modules/<host>/r2-runtime.nix` and `modules/<host>/imports.nix`
- `modules/security/r2-cloud-secrets.nix`
- `modules/home/r2-secrets.nix`
- `modules/security/sops-policy.nix`

## Not Covered

- Producer CI checks (`nix-R2-CloudFlare-Flake/scripts/ci/validate.sh`)

## Static Wiring Checks

Run from repo root:

```bash
# Verify flake input registration
rg -n 'r2-flake\.url' flake.nix
# Verify gated module imports from r2-flake
rg -n 'inputs\."r2-flake"\.(nixosModules|homeManagerModules)\.default' modules/lib/r2-runtime.nix
# Verify runtime service and program configurations
rg -n 'services\.r2-sync|services\.r2-restic|programs\.git-annex-r2|programs\.r2-cloud' modules/lib/r2-runtime.nix
# Verify per-host policy wiring
rg -n 'mkHostR2Module' modules/*/r2-runtime.nix
# Verify SOPS creation rule for r2 secrets
rg -n 'path_regex: secrets/r2\\.yaml' modules/security/sops-policy.nix
# Verify secret file references
rg -n 'r2-credentials\.env|r2-explorer\.env|cloudflare/r2/env' modules/security/r2-cloud-secrets.nix modules/home/r2-secrets.nix
```

Expected result:

- each command returns at least one hit
- no renamed path or option leaves these checks empty

## Evaluation and Build-Level Checks

```bash
nix flake check --accept-flake-config --no-build --offline
nix build .#nixosConfigurations.system76.config.system.build.toplevel
```

Expected result:

- both commands exit `0`
- no missing-option/module import errors for `r2` surfaces

## Runtime Presence Checks (after switch/boot)

The secret checks require `security.r2CloudSecrets.enable` on the host; the
unit checks additionally require the host R2 policy to enable the runtime.
Current host policies keep the runtime disabled, so absent `r2-*` units are
the expected state today.

```bash
test -s /run/secrets/r2/account-id
test -s /run/secrets/r2/credentials.env
test -s /run/secrets/r2/restic-password
systemctl status r2-mount-workspace --no-pager
systemctl status r2-restic-backup --no-pager
```

Expected result (on a host with the runtime enabled):

- secret files exist and are non-empty
- systemd units are present (and active/invokable according to host state)

## Drift Signals to Treat as Breakage

- `inputs."r2-flake".*` gated imports removed from `modules/lib/r2-runtime.nix`
- `programs.r2-cloud` assignment removed from `modules/lib/r2-runtime.nix`
- a host's `modules/<host>/r2-runtime.nix` no longer calls `mkHostR2Module`
- `secrets/r2.yaml` creation rule removed from `modules/security/sops-policy.nix`
- secret template paths changed without consumer path updates
