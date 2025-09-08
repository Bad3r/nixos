{ inputs, lib, ... }:
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
            # Update all input branches and record in superproject
            inputBranchesUpdateAll = pkgs.writeShellApplication {
              name = "input-branches-update-all";
              runtimeInputs = [
                pkgs.git
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

                echo "==> Rebasing all input branches onto upstream"
                input-branches-rebase
                echo "==> Pushing all input branches to origin"
                input-branches-push-force

                echo "==> Recording updated submodule pointers in superproject"
                git add inputs
                if git diff --cached --quiet -- inputs; then
                  echo "No input bumps to commit."
                  exit 0
                fi
                git commit -m "chore(inputs): bump nixpkgs, home-manager, stylix"
                echo "Done: inputs bumped and recorded."
              '';
            };
            pushInputBranches = pkgs.writeShellApplication {
              name = "push-input-branches";
              text = ''
                                #!/usr/bin/env bash
                                set -euo pipefail

                                usage() {
                                  cat <<'EOF'
                Push input branches (inputs/*) to the repository origin.

                Usage:
                  push-input-branches [--debug] [<input> ...]

                Options:
                  --debug        Enable verbose logging (set -x) and extra diagnostics
                  -h, --help     Show this help

                Arguments:
                  <input>        Optional list of inputs to push (e.g., nixpkgs home-manager stylix).
                                 If omitted, auto-discovers inputs under inputs/*.

                Behavior:
                  - Ensures each submodule's push URL points to the superproject's origin
                  - Pushes HEAD of each input to its current branch (e.g., inputs/<branch>/<name>)
                  - Uses --force-with-lease and sets upstream on first push
                  - Verifies presence of the branch on origin
                EOF
                                }

                                DEBUG=0
                                ARGS=()
                                while [[ $# -gt 0 ]]; do
                                  case "$1" in
                                  --debug)
                                    DEBUG=1; shift;;
                                  -h|--help)
                                    usage; exit 0;;
                                  --)
                                    shift; break;;
                                  -*)
                                    echo "Unknown option: $1" >&2; usage; exit 2;;
                                  *)
                                    ARGS+=("$1"); shift;;
                                  esac
                                done

                                if [[ ''${DEBUG} -eq 1 ]]; then set -x; fi

                                ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
                                if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
                                  echo "Error: run this inside the superproject git repository" >&2
                                  exit 1
                                fi
                                cd "$ROOT"

                                PARENT_ORIGIN=$(git remote get-url --push origin 2>/dev/null || git remote get-url origin 2>/dev/null || true)
                                if [[ -z "$PARENT_ORIGIN" ]]; then
                                  echo "Error: could not resolve superproject origin push URL" >&2
                                  exit 1
                                fi

                                declare -a TARGETS=()
                                if [[ ''${#ARGS[@]} -gt 0 ]]; then
                                  for name in "''${ARGS[@]}"; do
                                    path="inputs/$name"
                                    if [[ -d "$path/.git" || -f "$path/.git" ]]; then
                                      TARGETS+=("$name")
                                    else
                                      echo "Warning: skipped '$name' (no git repo at $path)" >&2
                                    fi
                                  done
                                else
                                  shopt -s nullglob
                                  for d in inputs/*; do
                                    [[ -d "$d" ]] || continue
                                    if [[ -d "$d/.git" || -f "$d/.git" ]]; then
                                      TARGETS+=("$(basename "$d")")
                                    fi
                                  done
                                  shopt -u nullglob
                                fi

                                if [[ ''${#TARGETS[@]} -eq 0 ]]; then
                                  echo "Error: no input submodules found under inputs/*" >&2
                                  exit 1
                                fi

                                echo "Superproject origin (push): $PARENT_ORIGIN"

                                for name in "''${TARGETS[@]}"; do
                                  path="inputs/$name"
                                  echo "==> Processing $name ($path)"

                                  if ! git -C "$path" remote get-url origin >/dev/null 2>&1; then
                                    git -C "$path" remote add origin "$PARENT_ORIGIN"
                                  fi
                                  git -C "$path" remote set-url --push origin "$PARENT_ORIGIN"

                                  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                                  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
                                    gm_branch=$(git config -f .gitmodules "submodule.$path.branch" 2>/dev/null || echo "")
                                    if [[ -n "$gm_branch" ]]; then
                                      branch="$gm_branch"
                                      echo "Info: detached HEAD; using .gitmodules branch '$branch'"
                                    else
                                      sp_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
                                      branch="inputs/$sp_branch/$name"
                                      echo "Info: detached HEAD; defaulting to '$branch'"
                                    fi
                                  fi

                                  echo "Pushing HEAD -> origin:$branch"
                                  git -C "$path" push --force-with-lease -u origin "HEAD:refs/heads/$branch"

                                  if git ls-remote --heads "$PARENT_ORIGIN" "$branch" | grep -qE "\srefs/heads/$branch$"; then
                                    echo "OK: origin has branch '$branch' for $name"
                                  else
                                    echo "Warning: could not verify branch '$branch' on origin for $name" >&2
                                  fi
                                done

                                echo "All requested input branches have been pushed."
              '';
              runtimeInputs = [
                pkgs.git
                pkgs.gnugrep
                pkgs.coreutils
                pkgs.gawk
              ];
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
            act
            jq
            yq
            ghActionsRun
            ghActionsList
            inputBranchesUpdateAll
            pushInputBranches
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
          echo "  input-branches-update-all - Rebase + push inputs, commit bumps"
          echo "  push-input-branches    - Push input branches (inputs/*) to origin"
          echo "  write-files            - Generate managed files (README.md, .actrc, .gitignore)"
          echo "  gh-actions-run [-n]    - Run all GitHub Actions locally (use -n for dry run)"
          echo "  gh-actions-list        - List discovered GitHub Actions jobs"
          echo ""
          ${config.pre-commit.installationScript}
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
