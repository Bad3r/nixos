# Input Branches Checklist

Use this to verify the input-branches workflow after changes. Check items in order; everything below assumes `.gitmodules` already lists `inputs/{nixpkgs,home-manager,stylix}` with `url = ./.` and `shallow = true`.

## Environment

- [ ] Running Nix ≥ 2.31.1 (or another release that supports `inputs.self.submodules`).
- [ ] `nix develop` succeeds and exposes the input-branches commands (`input-branches-catalog`).

## Flake Wiring

- [ ] `inputs.self.submodules = true` in `flake.nix`.
- [ ] Vendored inputs reference local paths (`git+file:./inputs/<name>` with `flake = true`).
- [ ] `inputs.input-branches` is present and follows `nixpkgs`.

## Module Setup (`modules/input-branches.nix`)

- [ ] Imports `inputs.input-branches.flakeModules.default`.
- [ ] `input-branches.inputs` lists upstreams for `nixpkgs`, `home-manager`, and `stylix`; `nixpkgs` sets `shallow = true`.
- [ ] Injects the mitigation: `imports = [ inputs.input-branches.modules.nixos.default ];`.
- [ ] Forces `nixpkgs.flake.source` to the local input (`lib.mkForce (rootPath + "/inputs/nixpkgs")`).
- [ ] per-system block exposes `input-branches.commands.all` via `make-shells.default.packages`.
- [ ] per-system block excludes `${baseDir}/*` from treefmt.

## Dev Shell & Commands

- [ ] `input-branches-init` exists (first-time initialisation).
- [ ] `update-input-branches` rebases, pushes, and refreshes `flake.lock` without prompting for manual fixes.
- [ ] `input-branches-catalog` lists configured inputs along with remote branches.
- [ ] `input-branches-push-force` is available for rare force-pushes.

## CI

- [ ] `.github/workflows/check.yml` uses `actions/checkout@v4` with `submodules: true` and `fetch-depth: 0`.

## Troubleshooting Aids

- [ ] `docs/INPUT-BRANCHES-COMMON-ISSUES.md` reflects current recovery steps (push missing commit, rehydrate nixpkgs, etc.).
- [ ] README documents the helper command (`update-input-branches`).

## Validation Pass

Run, in order:

- [ ] `nix fmt`
- [ ] `nix develop -c pre-commit run --all-files`
- [ ] `generation-manager score` (target ≥ 90/90)
- [ ] `nix flake check --accept-flake-config`

## Post-Update

- [ ] Push `inputs/<branch>/<name>` branches (the helper prints suggested `git push` commands).
- [ ] Commit the updated gitlinks and `flake.lock`.
