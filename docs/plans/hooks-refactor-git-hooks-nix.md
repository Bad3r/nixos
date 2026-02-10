# Hooks Refactor Plan: git-hooks.nix Migration

## Objectives

- Replace Lefthook with `cachix/git-hooks.nix` as the single hook orchestrator.
- Split hooks into fast staged pre-commit checks and heavy pre-push verification.
- Remove unsafe hook behavior (auto-commit in hooks, `.git` path assumptions, CI-only change failures).
- Standardize secrets scanning on `gitleaks`.

## Scope

### In scope

- Flake input migration and module wiring for `git-hooks.nix`.
- New `pre-commit` hook topology and custom hook wrappers.
- Devshell, build script, and docs migration to `pre-commit` commands.
- Removal of Lefthook config, rc bootstrap, and Lefthook-specific modules.

### Out of scope

- Introducing unrelated new linters/formatters.
- Host-level deployment policy changes beyond hook tooling.

## Hook Topology

### pre-commit (staged-only)

- `check-json`
- `yamllint` (relaxed preset)
- `treefmt` (`--fail-on-change`)
- `deadnix`
- `statix` (staged files only)
- `typos` (project `.typos.toml`)
- `pre-commit-hook-ensure-sops` (restricted to `secrets/` patterns)

### pre-push and manual

- `gitleaks` (repo/history secret scan)
- `vulnix` (blocking by default, allow warning mode via env override)
- `managed-files-drift` (verify-only by default; optional `apply` mode, no nested commits)
- `apps-catalog-sync` (full consistency check)

## Safety Rules

- No hook may run `git commit`.
- No hook may bypass signing or hooks (`--no-verify`, `core.hooksPath=/dev/null`) for nested commits.
- Worktree-safe git paths only (`git rev-parse`), no assumptions about `.git` being a directory.

## Implementation Plan

1. Add flake input `git-hooks` and import `inputs.git-hooks.flakeModule`.
2. Add `modules/meta/pre-commit.nix` as source of truth for hook definitions.
3. Add/adjust custom hook packages:
   - `hook-gitleaks`
   - `hook-vulnix`
   - `hook-managed-files-drift`
   - `hook-apps-catalog-sync`
4. Update `modules/devshell.nix`:
   - remove Lefthook install/bootstrap flow
   - use `config.pre-commit.shellHook`
   - include hook runtime packages in shell environment
5. Update `build.sh` to run:
   - `nix develop -c pre-commit run --all-files --hook-stage manual`
6. Remove Lefthook artifacts:
   - `modules/meta/lefthook.nix`
   - `modules/apps/lefthook.nix`
   - `lefthook.yml`
   - `scripts/lefthook-rc.sh`
   - obsolete Lefthook-specific wrapper modules
7. Update docs and references to pre-commit workflow.
8. Regenerate managed files with `nix develop -c write-files`.
9. Validate with hook run and flake evaluation.

## Acceptance Criteria

- `lefthook` is no longer required for normal development flow.
- Hook installation is automatic via `git-hooks.nix` shell hook.
- `pre-commit` stage runs staged-only checks.
- Heavy checks run in `pre-push` and `manual` stages.
- `managed-files-drift` never creates commits from hook execution.
- `build.sh` and docs reference only `pre-commit` command paths.

## Verification Matrix

- `nix develop -c pre-commit run --all-files --hook-stage manual`
- `nix develop -c pre-commit run`
- `nix flake check --accept-flake-config --no-build`
- `nix develop -c write-files`

## Rollback Plan

- Revert migration commits in reverse order:
  1. Lefthook removal commit
  2. command/docs switch commit
  3. `git-hooks.nix` module introduction commit
- Restore previous branch/worktree if required.
