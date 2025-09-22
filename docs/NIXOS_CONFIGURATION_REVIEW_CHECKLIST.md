# NixOS Configuration Review Checklist

Follow this checklist when reviewing changes to the System76 host configuration (the only host defined today). Everything assumes you are at the repository root (`/home/vx/nixos`).

## 0. Pre-flight

- [ ] `nix develop` succeeds and drops you into the dev shell.
- [ ] `git status` shows a clean working tree after applying the proposed changes.
- [ ] Identify the target host (currently `system76`):
  ```bash
  nix flake show --accept-flake-config | rg 'nixosConfigurations.'
  ```

## 1. Mandatory Validation

Run these commands in order; a failing command blocks the review.

```bash
nix fmt
nix develop -c pre-commit run --all-files
generation-manager score      # expect ≥ 90/90
nix flake check --accept-flake-config
```

Capture the resulting score/output in the review notes.

## 2. Module Topology

- [ ] Confirm the base → pc → workstation chain is intact:
  ```bash
  rg 'flake.nixosModules\.(base|pc|workstation)' modules/base modules/pc modules/workstation
  ```
- [ ] Confirm roles compose apps via guarded lookups (no `with config.flake.nixosModules.apps;`). Pre-commit enforces this, but double-check diffs in `modules/roles/`.
- [ ] For any new module, ensure it exports under a namespace rather than importing by path.
- [ ] When a change touches Home Manager modules, review `modules/home-manager/nixos.nix` to ensure the default app list reflects the intended behaviour.

## 3. Host Review (`system76`)

Inspect the host bundle for regressions:

- [ ] `modules/system76/imports.nix` still imports the expected aliases:
  ```bash
  sed -n '1,120p' modules/system76/imports.nix
  ```
- [ ] Boot + hardware:
  ```bash
  sed -n '1,120p' modules/system76/boot.nix
  sed -n '1,200p' modules/system76/hardware-config.nix
  ```
  Validate:
  - Kernel packages (`pkgs.linuxPackages_latest`).
  - LUKS devices defined in `hardware-config.nix` match expectations.
  - `/data` ownership unit exists (ensures runtime chown).
- [ ] NVIDIA configuration (`modules/system76/nvidia-gpu.nix`) enables the driver and blacklists nouveau.
- [ ] Networking (`modules/system76/network.nix`) keeps the firewall defaults and NetworkManager enabled.
- [ ] State version (`modules/system76/state-version.nix`) is unchanged unless a migration is intentional.

## 4. Security & Secrets

- [ ] Review `modules/security/secrets.nix` for any new secret declarations. They must guard on `pathExists`, set `mode = "0400"`, and inherit owner from `config.flake.lib.meta.owner.username`.
- [ ] If secrets changed, ensure the accompanying documentation (`docs/sops-nixos.md`, `docs/SECRETS_ACT.md`) was updated or still applies.
- [ ] Check for new network exposure:
  ```bash
  rg 'openFirewall' modules -n
  rg 'allowedTCPPorts' modules -n
  ```
  Confirm any newly opened ports are justified.

## 5. Packages & Services

- [ ] Diff the package sets when relevant:
  ```bash
  nix eval --json .#nixosConfigurations.system76.config.environment.systemPackages | jq 'length'
  ```
  (Use `nix build` with `nix-diff` for deeper analysis when large changes occur.)
- [ ] Scan service toggles:
  ```bash
  rg '\.enable = true;' modules/system76 modules/base modules/workstation
  ```
  Pay attention to newly enabled long-running services.

## 6. Documentation & Metadata

- [ ] Ensure modified behaviour is documented (README, relevant `docs/*.md`).
- [ ] If modules were renamed/moved, confirm `_` prefixes guard unfinished work and `write-files` was run if managed files changed.

## 7. Final Notes

- Summarise findings, including validation command output and any manual testing performed.
- Call out follow-up actions (e.g., secret rotation, upstream patches) when necessary.
