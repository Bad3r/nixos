# Input Branches Adoption Plan

## Goal
Adopt the input-branches pattern used in infra to keep patched flake inputs (e.g., nixpkgs, home-manager, stylix) as branches inside this repo and reference them as submodules under `inputs/`. This improves patch tracking and rebasing while preserving upstream-first work.

## Changes Required
- Flake inputs:
  - Keep `inputs.self.submodules = true`.
  - Point selected inputs to local paths: `nixpkgs.url = "./inputs/nixpkgs"`, `home-manager.url = "./inputs/home-manager"`, `stylix.url = "./inputs/stylix"` (match infra). Maintain `follows` as today.
  - Keep other inputs remote as-is.
- Module: add `modules/meta/input-branches.nix` extension (new file or expand existing) to:
  - `imports = [ inputs.input-branches.flakeModules.default ];`
  - Configure upstreams:
    - nixpkgs: `https://github.com/NixOS/nixpkgs.git` `ref = "nixos-unstable"` or current channel
    - home-manager: `https://github.com/nix-community/home-manager.git` `ref = "master"`
    - stylix: `https://github.com/nix-community/stylix.git` `ref = "master"`
  - Force nixpkgs to local path: `nixpkgs.flake.source = lib.mkForce (rootPath + "/inputs/nixpkgs");`
  - perSystem: expose `config.input-branches.commands.all` in the dev shell, exclude `inputs/*` from treefmt, install a `pre-push` hook that verifies submodules are clean and pushed (see infra’s `check-submodules-pushed`).
- Dev shell and hooks:
  - `modules/devshell.nix` already enables treefmt and pre-commit; extend to include the input-branches commands package and the pre-push hook (above).
- CI:
  - Ensure Actions checkout uses submodules: `actions/checkout@v4` with `submodules: true`.

## Initialization (one-time, no builds)
- `nix develop`
- `input-branches-init` (creates `inputs/<name>/` submodules on `inputs/main/<name>` branches)
- Commit generated files: `git add inputs/ .gitmodules && git commit -m "inputs: init input branches"`

## Ongoing Workflow (no builds)
- Validation only: `nix fmt`, `nix develop -c pre-commit run --all-files`, `generation-manager score`, `nix flake check --accept-flake-config`.
- Update a patched input:
  - Edit under `inputs/<name>` on `inputs/main/<name>`; commit and push that branch.
  - Update reference in main: `git add inputs/<name> && git commit -m "<name>: bump"`.
  - Rebase: `input-branches-rebase-<name>` (or loop over all); then `input-branches-push-force`.
- Never run build/switch/GC commands from this repo automation.

## Rollback & Exit
- To revert: reset flake inputs back to GitHub URLs, remove submodules (`git rm -f inputs/<name>`), commit `.gitmodules` changes, and drop the module import.

## Risks & Notes
- Repo grows due to embedded inputs; treefmt excludes `inputs/*` to keep formatting fast.
- Pre-push hook prevents broken submodule refs.
- This repo uses `bad3r/input-branches`; keep that input unless switching to the upstream module.
