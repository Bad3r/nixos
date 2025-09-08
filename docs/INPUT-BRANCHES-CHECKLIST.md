# Input Branches Adoption Checklist

Use this checklist to track implementation of the input-branches workflow in this repo. See `docs/INPUT-BRANCHES-PLAN.md` for rationale and examples.

## Prerequisites

- [ ] Nix ≥ 2.27 installed
- [ ] Experimental features enabled (`nix-command flakes pipe-operators`)
- [ ] Primary git remote is named `origin`

## Flake Inputs

- [ ] `inputs.self.submodules = true` set
- [ ] Add `input-branches` input (this repo uses `github:mightyiam/input-branches`)
- [ ] Redirect selected inputs to local paths:
  - [ ] `nixpkgs.url = "./inputs/nixpkgs"`
  - [ ] `home-manager.url = "./inputs/home-manager"` (follows `nixpkgs`)
  - [ ] `stylix.url = "./inputs/stylix"` (follows `nixpkgs`)
- [ ] Keep other inputs remote as-is
- [ ] Confirm inputs are `flake = true` (have `flake.nix`)

## Module Wiring (`modules/meta/input-branches.nix`)

- [ ] Import flake module: `inputs.input-branches.flakeModules.default`
- [ ] Configure upstreams:
  - [ ] nixpkgs upstream (ref e.g. `nixos-unstable`, `shallow = true`)
  - [ ] home-manager upstream (`master`)
  - [ ] stylix upstream (`master`)
- [ ] Import NixOS mitigation: `inputs.input-branches.modules.nixos.default`
- [ ] perSystem:
  - [ ] Expose commands: `make-shells.default.packages = config.input-branches.commands.all`
  - [ ] Exclude `inputs/*` from treefmt
  - [ ] Add `check-submodules-pushed` pre-push hook

## Dev Shell / DX

- [ ] Ensure pre-commit dev shell is included (`inputsFrom = [ config.pre-commit.devShell ]`)
- [ ] Confirm `input-branches-catalog` appears in shell help

## CI

- [ ] actions/checkout@v4 uses `submodules: true`
- [ ] actions/checkout@v4 uses `fetch-depth: 0`

## Submodule Configuration

- [ ] `.gitmodules` uses portable URLs (`url = ./.`) for all inputs
- [ ] Branch hints present (e.g., `branch = inputs/<current-branch>/<name>`) for each input

## Initialization (one-time)

- [ ] Enter shell: `nix develop`
- [ ] Initialize inputs: `input-branches-init`
- [ ] Commit: `git add inputs/ .gitmodules && git commit -m "inputs: init input branches"`

## Post-Clone Reminder

- [ ] Document: `git submodule update --init --recursive`

## Ongoing Workflow (no builds)

- [ ] Validation pass: `nix fmt` → `nix develop -c pre-commit run --all-files` → `generation-manager score` → `nix flake check --accept-flake-config`
- [ ] Update input flow: edit under `inputs/<name>` on `inputs/<current-branch>/<name>` → commit/push branch → `git add inputs/<name>` → commit bump
- [ ] Rebase as needed: `input-branches-rebase-<name>` (or all) → `input-branches-push-force`
- [ ] Do not run build/switch/GC commands

## Notes

- [ ] Branch naming noted: `inputs/<current-branch>/<name>`
- [ ] “Dirty superproject” workaround documented if needed (`touch dirt && git add -N dirt`)
