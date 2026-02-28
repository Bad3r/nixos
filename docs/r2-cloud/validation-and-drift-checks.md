# Validation and Drift Checks

## Scope

Operator checks to confirm `r2-flake` integration is intact and still mapped to
expected files/options in this repository.

## Source of Truth

- `flake.nix`
- `modules/system76/imports.nix`
- `modules/system76/r2-runtime.nix`
- `modules/security/r2-cloud-secrets.nix`
- `modules/home/r2-secrets.nix`
- `modules/security/sops-policy.nix`

## Not Covered

- Producer CI checks (`nix-R2-CloudFlare-Flake/scripts/ci/validate.sh`)

## Static Wiring Checks

Run from repo root:

```bash
# Verify flake input registration
rg -n 'r2-flake\\.url' flake.nix
# Verify module imports from r2-flake
rg -n 'inputs\\.r2-flake\\.(nixosModules|homeManagerModules)\\.default' modules/system76/imports.nix
# Verify runtime service and program configurations
rg -n 'services\\.r2-sync|services\\.r2-restic|programs\\.git-annex-r2|programs\\.r2-cloud' modules/system76/r2-runtime.nix
# Verify SOPS creation rule for r2 secrets
rg -n 'path_regex: secrets/r2\\\.yaml' modules/security/sops-policy.nix
# Verify secret file references
rg -n 'r2-credentials\\.env|r2-explorer\\.env|cloudflare/r2/env' modules/security/r2-cloud-secrets.nix modules/home/r2-secrets.nix
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

```bash
test -s /run/secrets/r2/account-id
test -s /run/secrets/r2/credentials.env
test -s /run/secrets/r2/restic-password
systemctl status r2-mount-workspace --no-pager
systemctl status r2-restic-backup --no-pager
```

Expected result:

- secret files exist and are non-empty
- systemd units are present (and active/invokable according to host state)

## Drift Signals to Treat as Breakage

- `inputs.r2-flake.*` import removed from `modules/system76/imports.nix`
- `programs.r2-cloud` assignment removed from `modules/system76/r2-runtime.nix`
- `secrets/r2.yaml` creation rule removed from `modules/security/sops-policy.nix`
- secret template paths changed without consumer path updates
