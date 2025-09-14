{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.make-shell.flakeModules.default
  ];
  perSystem =
    psArgs@{ pkgs, config, ... }:
    {
      # Use make-shells pattern for better modularity
      make-shells.default = {
        packages =
          with pkgs;
          let
            # Update input branches and record in superproject
            updateInputBranches = pkgs.writeShellApplication {
              name = "update-input-branches";
              runtimeInputs = [
                pkgs.git
                pkgs.gnugrep
                pkgs.gnused
              ]
              ++ (if psArgs.config ? input-branches then psArgs.config.input-branches.commands.all else [ ]);
              text = ''
                set -euo pipefail
                ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
                if [ -z "''${ROOT}" ] || [ ! -d "''${ROOT}/.git" ]; then
                  echo "Error: run inside the superproject git repository" >&2
                  exit 1
                fi
                cd "''${ROOT}"

                echo "==> Preparing submodules (normalize remotes, clean worktrees)"
                # Ensure submodules fetch from the superproject origin (not the relative './.')
                PARENT_ORIGIN=$(git remote get-url --push origin 2>/dev/null || git remote get-url origin 2>/dev/null || true)
                if [ -z "''${PARENT_ORIGIN}" ]; then
                  echo "Error: could not resolve superproject origin URL" >&2
                  exit 1
                fi
                SP_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
                if [ -d inputs ]; then
                  for d in inputs/*; do
                    [ -d "$d" ] || continue
                    if [ -d "$d/.git" ] || [ -f "$d/.git" ]; then
                      git -C "$d" remote set-url origin "''${PARENT_ORIGIN}"
                      git -C "$d" remote set-url --push origin "''${PARENT_ORIGIN}"
                      # Determine intended branch for this input
                      name=$(basename "$d")
                      gm_branch=$(git config -f .gitmodules "submodule.$d.branch" 2>/dev/null || true)
                      target_branch=''${gm_branch:-inputs/''${SP_BRANCH}/''${name}}

                      # If the repo is in an aborted temp state (unborn HEAD, temp branch, or dirty index),
                      # try to restore it to the target branch tip from local or origin.
                      current_branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                      if ! git -C "$d" rev-parse --verify -q HEAD >/dev/null 2>&1 \
                        || [ "$current_branch" = "_input-branches-temp" ] \
                        || [ -n "$(git -C "$d" status --porcelain)" ]; then
                        # Prefer local branch if it exists
                        if git -C "$d" rev-parse --verify -q "$target_branch" >/dev/null 2>&1; then
                          git -C "$d" checkout -f "$target_branch" >/dev/null 2>&1 || true
                          git -C "$d" reset --hard "$target_branch" >/dev/null 2>&1 || true
                        else
                          # Fall back to origin if accessible
                          git -C "$d" fetch origin "refs/heads/$target_branch:refs/remotes/origin/$target_branch" >/dev/null 2>&1 || true
                          if git -C "$d" rev-parse --verify -q "origin/$target_branch" >/dev/null 2>&1; then
                            git -C "$d" checkout -B "$target_branch" "origin/$target_branch" >/dev/null 2>&1 || true
                            git -C "$d" reset --hard "origin/$target_branch" >/dev/null 2>&1 || true
                          fi
                        fi
                      fi
                      # Final clean slate for rebase operations
                      git -C "$d" reset --hard HEAD >/dev/null 2>&1 || true
                      git -C "$d" clean -fdxq || true
                    fi
                  done
                fi

                echo "==> Rebasing inputs (skip nixpkgs by default; set REBASE_NIXPKGS=1 to include)"
                if command -v input-branch-rebase-home-manager >/dev/null 2>&1; then
                  input-branch-rebase-home-manager || true
                fi
                if command -v input-branch-rebase-stylix >/dev/null 2>&1; then
                  input-branch-rebase-stylix || true
                fi
                if [ -n "''${REBASE_NIXPKGS:-}" ]; then
                  if command -v input-branch-rebase-nixpkgs >/dev/null 2>&1; then
                    HYDRATE_NIXPKGS="''${HYDRATE_NIXPKGS:-}" input-branch-rebase-nixpkgs || true
                  fi
                else
                  echo "Skipping nixpkgs rebase (REBASE_NIXPKGS unset)."
                fi
                # Maintain squashed policy for selected inputs by resetting them back to origin tip
                # Currently: keep home-manager squashed (avoid pulling full upstream history into our branch)
                if [ -d inputs/home-manager ]; then
                  hm_branch=$(git config -f .gitmodules 'submodule.inputs/home-manager.branch' || true)
                  if [ -z "''${hm_branch}" ]; then
                    hm_branch="inputs/$(git rev-parse --abbrev-ref HEAD)/home-manager"
                  fi
                  git -C inputs/home-manager fetch origin "''${hm_branch}" || true
                  git -C inputs/home-manager reset --hard "origin/''${hm_branch}" >/dev/null 2>&1 || true
                fi

                echo "==> Ensuring submodule worktrees are clean"
                if [ -d inputs ]; then
                  for d in inputs/*; do
                    [ -d "$d" ] || continue
                    if [ -d "$d/.git" ] || [ -f "$d/.git" ]; then
                      git -C "$d" reset --hard HEAD >/dev/null 2>&1 || true
                      git -C "$d" clean -fdxq || true
                    fi
                  done
                fi

                echo "==> Staging updated input pointers (gitlinks)"
                git add -u inputs || true

                echo "==> Committing input pointer updates (inputs-only)"
                if git diff --cached --quiet -- inputs; then
                  echo "No input bumps to commit."
                else
                  # Guard: refuse if non-input files are staged unless explicitly allowed
                  if git diff --name-only --cached | grep -v '^inputs/' -q; then
                    if [ "''${ALLOW_NON_INPUT_STAGED:-}" != "1" ]; then
                      echo "Refusing to commit: non-input files are staged." >&2
                      echo "Unstage them or set ALLOW_NON_INPUT_STAGED=1 to override." >&2
                      exit 2
                    fi
                  fi
                  git -c core.hooksPath=/dev/null commit --only --no-verify -m "chore(inputs): bump inputs (gitlinks only)" -- inputs
                fi

                echo "==> Pushing input branches to origin (force-with-lease)"
                SP_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
                if [ -d inputs ]; then
                  for path in inputs/*; do
                    [ -d "$path" ] || continue
                    if [ ! -d "$path/.git" ] && [ ! -f "$path/.git" ]; then continue; fi
                    name=$(basename "$path")
                    echo "Superproject origin (push): $PARENT_ORIGIN"
                    echo "==> Processing $name ($path)"

                    # Ensure submodule origin push url points to superproject origin
                    if ! git -C "$path" remote get-url origin >/dev/null 2>&1; then
                      git -C "$path" remote add origin "$PARENT_ORIGIN"
                    fi
                    git -C "$path" remote set-url --push origin "$PARENT_ORIGIN"

                    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
                      gm_branch=$(git config -f .gitmodules "submodule.$path.branch" 2>/dev/null || echo "")
                      if [ -n "$gm_branch" ]; then
                        branch="$gm_branch"
                        echo "Info: detached HEAD; using .gitmodules branch '$branch'"
                      else
                        branch="inputs/$SP_BRANCH/$name"
                        echo "Info: detached HEAD; defaulting to '$branch'"
                      fi
                    fi

                    # Hydrate commit graph for promisor remotes without pulling full blobs for nixpkgs
                    # This preserves shallow+blobless setup per docs while keeping push safety for smaller inputs.
                    if git -C "$path" remote get-url upstream >/dev/null 2>&1; then
                      up_head=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name upstream/HEAD 2>/dev/null | sed 's|^upstream/||' || true)
                      # Allow override to fully hydrate nixpkgs when explicitly requested
                      if [ "$name" = "nixpkgs" ] && [ -z "''${HYDRATE_NIXPKGS:-}" ]; then
                        if [ -n "$up_head" ]; then
                          git -C "$path" fetch --filter=blob:none upstream "$up_head" || true
                        else
                          git -C "$path" fetch --filter=blob:none upstream || true
                        fi
                      else
                        if [ -n "$up_head" ]; then
                          git -C "$path" fetch --no-filter upstream "$up_head" || true
                        else
                          git -C "$path" fetch --no-filter upstream || true
                        fi
                      fi
                    fi

                    echo "Pushing HEAD -> origin:$branch"
                    if ! git -c core.hooksPath=/dev/null -C "$path" push --force-with-lease -u origin "HEAD:refs/heads/$branch"; then
                      # Refresh remote state and retry once (handles 'stale info')
                      git -C "$path" fetch origin "refs/heads/$branch:refs/remotes/origin/$branch" || true
                      git -c core.hooksPath=/dev/null -C "$path" push --force-with-lease -u origin "HEAD:refs/heads/$branch" || {
                        echo "Error: push failed for $name" >&2
                        exit 70
                      }
                    fi

                    if git ls-remote --heads "$PARENT_ORIGIN" "$branch" | grep -qE "\srefs/heads/$branch$"; then
                      echo "OK: origin has branch '$branch' for $name"
                    else
                      echo "Warning: could not verify branch '$branch' on origin for $name" >&2
                    fi
                  done
                fi

                echo "==> Recording updated submodule pointers in superproject"
                # Guard: refuse if non-input files are already staged (unless overridden)
                if git diff --name-only --cached | grep -v '^inputs/' -q; then
                  if [ "''${ALLOW_NON_INPUT_STAGED:-}" != "1" ]; then
                    echo "Refusing to commit: non-input files are staged." >&2
                    echo "Unstage them or set ALLOW_NON_INPUT_STAGED=1 to override." >&2
                    exit 2
                  fi
                fi

                echo "==> Updating flake.lock to track local inputs/* HEADs"
                # Keep the lock file in sync with local inputs so evaluation uses the updated commits
                # without manual 'nix flake lock' runs. Only update inputs/* that exist locally.
                LOCK_UPDATED=0
                if [ -d inputs/nixpkgs ]; then
                  nix --accept-flake-config flake update --update-input nixpkgs || true
                  LOCK_UPDATED=1
                fi
                if [ -d inputs/home-manager ]; then
                  nix --accept-flake-config flake update --update-input home-manager || true
                  LOCK_UPDATED=1
                fi
                if [ -d inputs/stylix ]; then
                  nix --accept-flake-config flake update --update-input stylix || true
                  LOCK_UPDATED=1
                fi
                if [ """$LOCK_UPDATED""" = 1 ] && git diff --quiet -- flake.lock; then
                  : # no changes
                elif [ """$LOCK_UPDATED""" = 1 ]; then
                  git -c core.hooksPath=/dev/null add flake.lock
                  git -c core.hooksPath=/dev/null commit --no-verify -m "chore(lock): update flake.lock for local inputs"
                fi

                echo "Done: inputs bumped and recorded."
              '';
            };

            inputBranchesCatalog = pkgs.writeShellApplication {
              name = "input-branches-catalog";
              text = ''
                set -euo pipefail
                # Find input-branches commands in PATH
                found=$(
                  IFS=:
                  for d in $PATH; do
                    ls -1 "$d"/input-branches-* "$d"/input-branch-* 2>/dev/null || true
                  done | awk 'NF' | sort -u
                )
                if [ -z "''${found}" ]; then
                  echo "No input-branches commands found in PATH."
                  echo "If you expect them, enable the input-branches module and add its commands to the dev shell."
                  exit 0
                fi
                echo "Input-branches command catalog:";
                echo "''${found}"
              '';
            };
            ghActionsRun = pkgs.writeShellApplication {
              name = "gh-actions-run";
              text = ''
                set -euo pipefail
                DRY=""
                JOB=""
                EXTRA=()
                # Secret file auto-detection
                DEFAULT_SECRET_FILE="/etc/act/secrets.env"
                SECRET_FILE="''${ACT_SECRETS_FILE:-}"
                if [ -z "''${SECRET_FILE}" ] && [ -f "''${DEFAULT_SECRET_FILE}" ]; then
                  SECRET_FILE="''${DEFAULT_SECRET_FILE}"
                fi
                while [ $# -gt 0 ]; do
                  case "$1" in
                    -n|--dry-run)
                      DRY="-n"; shift;;
                    -j)
                      shift;
                      if [ $# -gt 0 ]; then
                        JOB="$1"; shift;
                      else
                        echo "gh-actions-run: -j requires a job name" >&2; exit 2;
                      fi;;
                    --secret-file)
                      shift; SECRET_FILE="''${1:-}"; if [ -n "$SECRET_FILE" ]; then shift; fi;;
                    --)
                      shift; break;;
                    -*)
                      EXTRA+=("$1"); shift;;
                    *)
                      if [ -z "$JOB" ]; then JOB="$1"; shift; else EXTRA+=("$1"); shift; fi;;
                  esac
                done

                if [ -z "''${DRY}" ]; then
                  if ! command -v docker >/dev/null 2>&1; then
                    echo "Docker not found. Install and start Docker, or use: gh-actions-run --dry-run" >&2
                    exit 1
                  fi
                fi

                if [ ! -d .github/workflows ]; then
                  echo "No workflows found at .github/workflows" >&2
                  exit 1
                fi

                # Run all workflows for the push event; include defaults for robustness
                if [ -n "$JOB" ]; then EXTRA=("-j" "$JOB" "''${EXTRA[@]}"); fi
                if [ -n "''${SECRET_FILE}" ]; then EXTRA=("--secret-file" "''${SECRET_FILE}" "''${EXTRA[@]}"); fi
                exec act ''${DRY} "''${EXTRA[@]}" \
                  -W .github/workflows \
                  -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-24.04 \
                  push "$@"
              '';
            };
            ghActionsList = pkgs.writeShellApplication {
              name = "gh-actions-list";
              text = ''
                set -euo pipefail
                if [ ! -d .github/workflows ]; then
                  echo "No workflows found at .github/workflows" >&2
                  exit 1
                fi
                exec act -W .github/workflows -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-24.04 -l
              '';
            };
          in
          [
            nixfmt-rfc-style
            nil # Nix LSP
            nix-tree
            nix-diff
            zsh
            act
            jq
            yq
            ghActionsRun
            ghActionsList
            updateInputBranches
            inputBranchesCatalog
            config.packages.generation-manager
            config.treefmt.build.wrapper
          ]
          ++ (if psArgs.config ? input-branches then psArgs.config.input-branches.commands.all else [ ]);

        inputsFrom = [ config.pre-commit.devShell ];

        shellHook = ''
          echo "🚀 NixOS Configuration Development Shell"
          echo ""
          echo "Available commands:"
          echo "  nix flake check        - Validate the flake"
          echo "  nix fmt                - Format Nix files"
          echo "  pre-commit install     - Install git hooks"
          echo "  pre-commit run         - Run hooks on staged files"
          echo "  input-branches-catalog - List input-branches commands (if available)"
          echo "  update-input-branches  - Rebase inputs, push inputs/* branches, commit bumps"
          echo "  write-files            - Generate managed files (README.md, .actrc, .gitignore)"
          echo "  gh-actions-run [-n]    - Run all GitHub Actions locally (use -n for dry run)"
          echo "  gh-actions-list        - List discovered GitHub Actions jobs"
          echo ""
          ${config.pre-commit.installationScript}

          # Prefer zsh for interactive sessions
          if [ -n "''${PS1-}" ] && [ -z "''${ZSH_VERSION-}" ] && [ -t 1 ]; then
            export SHELL="${pkgs.zsh}/bin/zsh"
            exec "${pkgs.zsh}/bin/zsh" -l
          fi
        '';
      };

      # Configure treefmt
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          prettier.enable = true;
          shfmt.enable = true;
        };
      };
    };
}
