# Input Branches Adoption Plan

## Goal

Adopt the input-branches pattern used in infra to keep patched flake inputs (e.g., nixpkgs, home-manager, stylix) as branches inside this repo and reference them as submodules under `inputs/`. This improves patch tracking and rebasing while preserving upstream-first work.

## Prerequisites

- Nix 2.27+ with experimental features enabled:
  ```nix
  experimental-features = nix-command flakes pipe-operators
  ```

## Changes Required

- Flake inputs:
  - Keep `inputs.self.submodules = true`.
  - Point selected inputs to local paths: `nixpkgs.url = "./inputs/nixpkgs"`, `home-manager.url = "./inputs/home-manager"`, `stylix.url = "./inputs/stylix"` (match infra). Maintain `follows` as today.
  - Keep other inputs remote as-is.
  - Branch naming: commands derive branches as `inputs/<current-branch>/<name>` (examples often use `main`).
  - Remote naming: ensure the primary remote is `origin` (commands push to `origin`).
- Module: add `modules/input-branches.nix` (new file) to:
  - `imports = [ inputs.input-branches.flakeModules.default ];`
  - Configure upstreams with shallow clone for nixpkgs:
    ```nix
    input-branches.inputs = {
      nixpkgs = {
        upstream = {
          url = "github:NixOS/nixpkgs";
          ref = "nixpkgs-unstable";  # Standard unstable branch
        };
        shallow = true;  # Saves ~3GB disk space
      };
      home-manager.upstream = {
        url = "github:nix-community/home-manager";
        ref = "master";
      };
      stylix.upstream = {
        url = "github:nix-community/stylix";
        ref = "master";
      };
    };
    ```
  - Import the provided NixOS mitigation module: `imports = [ inputs.input-branches.modules.nixos.default ];` (disables git metadata and sets `nixpkgs.flake.source = null` to avoid superproject inclusion). This repo forces a local registry entry to match infra: `nixpkgs.flake.source = lib.mkForce (rootPath + "/inputs/nixpkgs");` — drop this override if not needed in your setup.

### Shallow/Blobless Policy for nixpkgs

- nixpkgs is maintained as a shallow, partial clone:
  - `shallow = true` in `.gitmodules` for `inputs/nixpkgs`
  - `remote.upstream.promisor = true` and `remote.upstream.partialclonefilter = blob:none`
  - Optional: mirror the promisor/partialclonefilter on `remote.origin` inside the submodule
- Dev workflow preserves bloblessness:
  - The `update-input-branches` helper fetches nixpkgs with `--filter=blob:none` by default and only hydrates commit graphs.
  - To opt-in to full hydration (rarely needed), set an environment variable when running the helper:

    ```bash
    HYDRATE_NIXPKGS=1 update-input-branches
    ```

  - This keeps day-to-day operations fast and disk usage small, while allowing explicit full hydration when required.
  - perSystem configuration:

    ```nix
    perSystem = { config, pkgs, ... }: {
      make-shells.default.packages = config.input-branches.commands.all;
      treefmt.settings.global.excludes = [ "${config.input-branches.baseDir}/*" ];

      # Pre-push hook to ensure submodules are pushed
      pre-commit.settings.hooks.check-submodules-pushed = {
        enable = true;
        stages = [ "pre-push" ];
        always_run = true;
        verbose = true;
        entry =
          pkgs.writeShellApplication {
            name = "check-submodules-pushed";
            runtimeInputs = [
              pkgs.git
              pkgs.gnugrep
            ];
            text =
              config.input-branches.inputs
              |> lib.attrValues
              |> map (
                { path_, ... }:
                ''
                  (
                    unset GIT_DIR
                    cd ${path_}
                    current_commit=$(git rev-parse --quiet HEAD)
                    [ -z "$current_commit" ] && {
                      echo "Error: could not find HEAD of submodule ${path_}"
                      exit 1
                    }
                    status=$(git status --porcelain)
                    echo "$status" | grep -q . && {
                      echo "Error: submodule ${path_} not clean"
                      exit 1
                    }
                    ref='${v.upstream.ref or "master"}'
                    # Shallow, blobless fetch for speed
                    git fetch --depth=1 --filter=blob:none upstream "$ref" || {
                      echo "Error: failed to fetch upstream/$ref for ${path_}"
                      exit 1
                    }
                    if ! git merge-base --is-ancestor "$current_commit" "upstream/$ref"; then
                      attempts=0
                      while [ $attempts -lt 10 ]; do
                        attempts=$((attempts+1))
                        git fetch --deepen=100 --filter=blob:none upstream "$ref" || break
                        if git merge-base --is-ancestor "$current_commit" "upstream/$ref"; then
                          break
                        fi
                      done
                      if ! git merge-base --is-ancestor "$current_commit" "upstream/$ref"; then
                        echo "Error: submodule ${path_} commit $current_commit is not reachable from upstream/$ref (after shallow fetch)"
                        exit 1
                      fi
                    fi
                  )
                ''
              )
              |> lib.concat [
                ''
                  set -o xtrace
                ''
              ]
              |> lib.concatLines;
          }
          |> lib.getExe;
      };
    };
    ```

- Dev shell and hooks:
  - `modules/devshell.nix` already enables treefmt and pre-commit; keep it as-is. Put the input-branches commands and pre-push hook in `modules/input-branches.nix` (above) to keep concerns separate. Keep `modules/meta/input-branches.nix` for metadata only.
  - CI:
  - Ensure Actions checkout uses submodules: `actions/checkout@v4` with `submodules: true` and `fetch-depth: 0`. Example:
    ```yaml
    - uses: actions/checkout@v4
      with:
        submodules: true
        fetch-depth: 0
    ```

### Submodule Configuration (portability)

- Use repo-relative URLs for portability in `.gitmodules` and add branch hints for clarity:

```ini
[submodule "inputs/nixpkgs"]
  path = inputs/nixpkgs
  url = ./.
  branch = inputs/<current-branch>/nixpkgs
  shallow = true
[submodule "inputs/home-manager"]
  path = inputs/home-manager
  url = ./.
  branch = inputs/<current-branch>/home-manager
  shallow = true
[submodule "inputs/stylix"]
  path = inputs/stylix
  url = ./.
  branch = inputs/<current-branch>/stylix
  shallow = true
```

- After editing `.gitmodules`, run `git submodule sync --recursive`.

## Initialization (one-time, no builds)

- `nix develop`
- `input-branches-init` (creates `inputs/<name>/` submodules on `inputs/<current-branch>/<name>`; branch name is derived from the current git branch)
- Commit generated files: `git add inputs/ .gitmodules && git commit -m "inputs: init input branches"`
- After editing `.gitmodules`, run: `git submodule sync --recursive`
- After a fresh clone: `git submodule update --init --recursive`.

### Recovery from size regressions (nixpkgs)

If nixpkgs becomes large (lost shallow/partial state), reinitialize it:

1. Save the current SHA: `HEAD=$(git -C inputs/nixpkgs rev-parse HEAD)`
2. `git submodule deinit -f inputs/nixpkgs`
3. `rm -rf .git/modules/inputs/nixpkgs inputs/nixpkgs`
4. Recreate shallow+blobless (either):
   - `git submodule update --init --depth 1 inputs/nixpkgs` (works when relative `url=./.` resolves locally), or
   - Manual shallow clone from superproject origin, then absorb:
     - `git clone --filter=blob:none --depth 1 "$(git remote get-url origin)" inputs/nixpkgs`
     - `git -C inputs/nixpkgs fetch --filter=blob:none --depth 1 origin inputs/<branch>/nixpkgs:inputs/<branch>/nixpkgs`
     - `git submodule absorbgitdirs inputs/nixpkgs`
5. Ensure upstream promisor+filter: add `upstream` and set `promisor=true`, `partialclonefilter=blob:none`
6. `git -C inputs/nixpkgs checkout inputs/<branch>/nixpkgs`

## Ongoing Workflow (no builds)

- Validation checks (run before pushing):
  - `nix fmt` - Format all Nix files
  - `nix develop -c pre-commit run --all-files` - Run all pre-commit hooks (pre-commit stage)
  - `generation-manager score` - Project-specific validation
  - `nix flake check --accept-flake-config` - Verify flake outputs
  - These explicit validation steps ensure CI/CD alignment and catch issues early
  - Note: the pre-push hook runs on `git push`. To run it manually via pre-commit: `nix develop -c pre-commit run --hook-stage pre-push --all-files`.
- Update a patched input:
  - Edit under `inputs/<name>` on `inputs/<current-branch>/<name>`; commit and push that branch.
  - Update reference in main: `git add inputs/<name> && git commit -m "<name>: bump"`.
  - Rebase: `input-branches-rebase-<name>` (or loop over all); then `input-branches-push-force`.
- Never run build/switch/GC commands from this repo automation.

## Rollback & Exit

- To revert: reset flake inputs back to GitHub URLs, remove submodules (`git rm -f inputs/<name>`), commit `.gitmodules` changes, and drop the module import.

## Risks & Notes

- Repo grows due to embedded inputs; treefmt excludes `inputs/*` to keep formatting fast.
- Pre-push hook prevents broken submodule refs.
- Minimal Nix version 2.27+ (requires `inputs.self.submodules`).
- Use git checkout (not tarball) and enable submodules in CI (`actions/checkout@v4` with `submodules: true`).
- Each input must be `flake = true` (have a `flake.nix`).
- Superproject clean-state caveat: if needed, make the worktree dirty before Nix fetches submodules (see upstream README workaround).

## Code Examples

Example flake input redirects (partial):

```nix
{
  inputs = {
    self.submodules = true;
    input-branches.url = "github:mightyiam/input-branches";

    nixpkgs.url = "./inputs/nixpkgs";
    home-manager = {
      url = "./inputs/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "./inputs/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Note: Examples may use pipe operators; equivalent expressions using standard lib combinators are acceptable.
