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
- [ ] Mark all inputs as shallow in `.gitmodules` (`shallow = true`)
- [ ] For `inputs/nixpkgs`, verify partial clone settings:
  - [ ] `git -C inputs/nixpkgs config remote.upstream.promisor true`
  - [ ] `git -C inputs/nixpkgs config remote.upstream.partialclonefilter blob:none`
  - [ ] Optional: same promisor/partialclonefilter on `remote.origin`

## Initialization (one-time)

- [ ] Enter shell: `nix develop`
- [ ] Initialize inputs: `input-branches-init`
- [ ] Commit: `git add inputs/ .gitmodules && git commit -m "inputs: init input branches"`
 - [ ] Sync submodule config after editing `.gitmodules`: `git submodule sync --recursive`

## Post-Clone Reminder

- [ ] Document: `git submodule update --init --recursive`

## Ongoing Workflow (no builds)

- [ ] Validation pass: `nix fmt` → `nix develop -c pre-commit run --all-files` → `generation-manager score` → `nix flake check --accept-flake-config`
- [ ] Update input flow: edit under `inputs/<name>` on `inputs/<current-branch>/<name>` → commit/push branch → `git add inputs/<name>` → commit bump
- [ ] Rebase as needed: `input-branches-rebase-<name>` (or all) → `input-branches-push-force`
- [ ] Do not run build/switch/GC commands

## Maintenance (size & recovery)

- If `inputs/nixpkgs` grows unexpectedly large (lost shallow/partial state):
  1. Record HEAD: `HEAD=$(git -C inputs/nixpkgs rev-parse HEAD)`
  2. `git submodule deinit -f inputs/nixpkgs`
  3. `rm -rf .git/modules/inputs/nixpkgs inputs/nixpkgs`
  4. Shallow+blobless re-init (one of):
     - `git submodule update --init --depth 1 inputs/nixpkgs` (works when relative url resolves locally), or
     - Manually clone and absorb:
       - `git clone --filter=blob:none --depth 1 "$(git remote get-url origin)" inputs/nixpkgs`
       - `git -C inputs/nixpkgs fetch --filter=blob:none --depth 1 origin inputs/<branch>/nixpkgs:inputs/<branch>/nixpkgs`
       - `git submodule absorbgitdirs inputs/nixpkgs`
  5. Ensure upstream partial clone: `git -C inputs/nixpkgs remote add upstream git@github.com:NixOS/nixpkgs.git || true` then set `promisor=true`, `partialclonefilter=blob:none` on `upstream`.
  6. Restore local branch if needed: `git -C inputs/nixpkgs checkout inputs/<branch>/nixpkgs`

- Keep `update-input-branches` default behavior (blobless for nixpkgs). To force full hydration in rare cases, set `HYDRATE_NIXPKGS=1`.

## Notes

- [ ] Branch naming noted: `inputs/<current-branch>/<name>`
- [ ] “Dirty superproject” workaround documented if needed (`touch dirt && git add -N dirt`)
