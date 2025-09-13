# Inputs Workflow (Vendored Submodules)

This repository vendors key inputs as git submodules under `inputs/` and consumes them via `git+file:` flake URLs. This preserves provenance (commit-based locking) while allowing offline evaluation.

## Inputs

- `inputs/nixpkgs` → `nixpkgs.url = git+file:./inputs/nixpkgs`
- `inputs/home-manager` → `home-manager.url = git+file:./inputs/home-manager`
- `inputs/stylix` → `stylix.url = git+file:./inputs/stylix`

## Typical Flow

1. Update an input (fast-forward, rebase, or cherry-pick) in its submodule worktree:
   - `git -C inputs/nixpkgs fetch origin <branch>`
   - `git -C inputs/nixpkgs checkout <commit-or-branch>`
2. Record the new submodule pointer in the superproject:
   - `git add inputs/nixpkgs`
   - `git commit -m "chore(inputs): bump nixpkgs"`
3. Optionally refresh the lock file (capturing the new commit ref):
   - `nix flake lock --update-input nixpkgs`
4. Push both:
   - Push the submodule commit to your origin branch (see below for a helper script)
   - Push the superproject with the updated gitlink and lock

## Pre‑Push Helper (Optional)

A helper script is provided at `scripts/pre-push-inputs.sh` to push input branches to your origin with a deterministic naming scheme:

- Branch name: `inputs/<superproject-branch>/<input-name>`
- Only acts on inputs that are git repositories present under `inputs/*`

Install it as a Git hook (optional):

```
ln -s ../../scripts/pre-push-inputs.sh .git/hooks/pre-push
```

Run it manually:

```
scripts/pre-push-inputs.sh
```

Notes:
- If you use this helper, ensure your remote authentication is configured for the superproject origin.
- The script will refuse to push if not run inside the superproject git worktree.

## Lock Hygiene

- Lock updates are optional, but recommended after bumping inputs: `nix flake lock --update-input <name>`
- Because inputs are `git+file:` repos, the lock captures the exact commit from the submodule worktree.
- Nix may warn that relative `git+file:` URLs are deprecated; they work today and can be migrated to absolute `file://` URLs if needed in the future.

## CI/Validation

- Run locally before pushing:
  - `nix fmt`
  - `nix develop -c pre-commit run --all-files`
  - `nix flake show` (quick evaluation snapshot)
  - `nix flake check` (full checks; may be heavier)

