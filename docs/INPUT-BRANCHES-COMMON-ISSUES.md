# Input Branches: Common Issue and Quick Fix

When using the input‑branches workflow (vendored inputs under `inputs/*`), a frequent cause of flake evaluation failures is a submodule commit that was never pushed to your monorepo’s `inputs/<branch>/<name>` branch.

## Symptoms

- `nix flake check` or any Nix command that evaluates the flake fails with errors like:

  ```
  … while fetching the input 'git+file:///path/to/repo?ref=refs/heads/main&rev=<superproject-sha>&submodules=1'

  … while fetching the input 'git+ssh://git@github.com/<owner>/<repo>.git/?ref=inputs/main/<name>&rev=<submodule-sha>&submodules=1'

  error: Cannot find Git revision '<submodule-sha>' in ref 'inputs/main/<name>' of repository 'ssh://git@github.com/<owner>/<repo>.git/'!
  ```

This can affect any of the three vendored inputs:

- `inputs/nixpkgs`
- `inputs/home-manager`
- `inputs/stylix`

## Root Cause

The superproject commits a gitlink for `inputs/<name>` pointing at a specific commit, but that commit does not exist on the remote branch `origin/inputs/<superproject-branch>/<name>`. This typically happens after rebasing or committing locally in `inputs/<name>` without pushing the branch to origin, and then committing the updated submodule pointer in the superproject.

## Quick Fix (Push → Update → Check)

1. Push the missing submodule commit to your monorepo, targeting the `inputs/<superproject-branch>/<name>` branch.

- Example for `stylix` on superproject branch `main`:

  ```bash
  git -C inputs/stylix push -u origin HEAD:refs/heads/inputs/main/stylix
  ```

- Generic pattern for any input (`<name>` is one of `nixpkgs`, `home-manager`, `stylix`; `<sp_branch>` is your current superproject branch, e.g. `main`):

  ```bash
  git -C inputs/<name> push -u origin HEAD:refs/heads/inputs/<sp_branch>/<name>
  ```

2. Refresh the flake lock so it tracks the updated local input HEADs:

```bash
nix --accept-flake-config flake update
```

3. Re‑run checks:

```bash
nix --accept-flake-config flake check --show-trace
```

If the error was caused by an unpushed submodule commit, the above sequence resolves it.

## Diagnostics (optional)

- See which commit the superproject pins for an input:

  ```bash
  git ls-tree HEAD inputs/<name>
  # shows the gitlink SHA recorded by the superproject
  ```

- Verify the remote branch exists and contains that commit:

  ```bash
  # fetch branch tip first
  git fetch origin inputs/<sp_branch>/<name>:refs/remotes/origin/inputs/<sp_branch>/<name>
  # check ancestry (exit code 0 = present)
  git -C inputs/<name> merge-base --is-ancestor <gitlink-sha> origin/inputs/<sp_branch>/<name>
  ```

## Prevention

- Use the provided helper which rebases/pushes input branches and updates `flake.lock` in one go:

  ```bash
  nix develop -c update-input-branches
  ```

- Ensure CI checks out submodules with full history (already configured in this repo):
  - `actions/checkout@v4` with `submodules: true` and `fetch-depth: 0`.

## Notes

- The “add `allRefs = true;` to `fetchGit`” hint you may see in errors does not apply here; Nix is fetching your submodule from this repository. The correct fix is to ensure the submodule commit exists on the expected `inputs/<sp_branch>/<name>` branch and then refresh the lock.
