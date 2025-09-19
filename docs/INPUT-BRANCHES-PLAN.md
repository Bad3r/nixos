# Input Branches Adoption Plan

This repository vendors selected flake inputs (`nixpkgs`, `home-manager`, `stylix`) as Git submodules under `inputs/` and tracks local patches on branches named `inputs/<superproject-branch>/<name>`. The pattern matches the implementation in [`mightyiam/infra`](https://github.com/mightyiam/infra) and is enforced by `modules/input-branches.nix`.

## Status Snapshot (September 2025)

- ✅ `inputs.self.submodules = true` to expose submodule metadata to the flake evaluator.
- ✅ `nixpkgs`, `home-manager`, and `stylix` point at local `./inputs/*` paths with `flake = true`.
- ✅ `modules/input-branches.nix` imports the upstream flake module and rewires `nixpkgs.flake.source` to the local checkout.
- ✅ per-system glue exposes helper commands and tells treefmt to skip `inputs/*`.
- ✅ `.gitmodules` records each input with `url = ./.` and `shallow = true` for portability.
- ✅ GitHub Actions checks out submodules (`submodules: true`, `fetch-depth: 0`).
- ✅ `update-input-branches` helper keeps `inputs/nixpkgs` as a partial clone (blobless by default) and provides `HYDRATE_NIXPKGS` / `KEEP_WORKTREE` escape hatches.

## Prerequisites

- Use a recent Nix release that recognises `inputs.self.submodules` (repository tooling is tested with **Nix 2.31.1**).
- Ensure `nixConfig.extra-experimental-features = [ "pipe-operators" ]` is honoured (already set in `flake.nix`).
- Keep the primary remote named `origin`; helper scripts push and fetch from it.

## Required Wiring

1. **Flake Inputs** – already present in `flake.nix`:

   ```nix
   nixpkgs.url = "git+file:./inputs/nixpkgs";
   home-manager.url = "git+file:./inputs/home-manager";
   stylix.url = "git+file:./inputs/stylix";
   ```

2. **Module Import** – `modules/input-branches.nix`:
   - Imports `inputs.input-branches.flakeModules.default`.
   - Declares upstreams for all vendored inputs (nixpkgs uses `shallow = true`).
   - Forces `nixpkgs.flake.source` to the local checkout so evaluation never hits the network when submodules are present.
   - Exposes helper commands through `make-shells.default.packages` when the input-branches module is active.
   - Tells treefmt to ignore `inputs/*` (faster formatting).
   - Purposefully **does not** install a pre-push hook—pushing helpers live in the input-branches command set.

3. **Dev Shell Integration** – the default shell surfaces:
   - `input-branches-init`
   - `input-branches-catalog`
   - `update-input-branches`
   - `input-branches-rebase-all`
   - `input-branches-push-force`

## Workflow Summary

1. Enter the shell: `nix develop`.
2. Initialise (first-time only): `input-branches-init` then commit `.gitmodules` and the new submodule directories.
3. Update inputs:
   ```bash
   nix develop -c update-input-branches    # rebases, pushes, refreshes flake.lock
   ```
4. Run validation (never skip):
   ```bash
   nix fmt
   nix develop -c pre-commit run --all-files
   generation-manager score
   nix flake check --accept-flake-config
   ```
5. Push both the main branch and the `inputs/*` branches announced by the helper output.

## Troubleshooting

- **Flake evaluation fails with “Cannot find Git revision …”** → the submodule commit was not pushed. Follow `docs/INPUT-BRANCHES-COMMON-ISSUES.md`.
- **`inputs/nixpkgs` exploded in size** → run `git submodule deinit -f inputs/nixpkgs`, remove the directory, and re-run `update-input-branches`.
- **Need a hydrated worktree** → set `KEEP_WORKTREE=1`. Combine with `HYDRATE_NIXPKGS=1` to fetch blobs temporarily.

## Decommissioning

If you ever need to drop input branches, remove the submodules (`git rm inputs/<name>`), switch the flake inputs back to upstream URLs, clean up `.gitmodules`, and delete `modules/input-branches.nix` imports. Remember to update CI when you do this.
