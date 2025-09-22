{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.make-shell.flakeModules.default
  ];
  perSystem =
    psArgs@{ pkgs, config, ... }:
    {
      # Keep format checks fast and focused on this repo, not vendored inputs
      treefmt.settings.global.excludes = [ "inputs/*" ];

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

                echo "==> Syncing submodules"
                git submodule sync --recursive || true
                git submodule update --init --recursive || true

                status=0
                if command -v input-branches-rebase >/dev/null 2>&1; then
                  if ! input-branches-rebase; then
                    status=$?
                    echo "Warning: input-branches-rebase exited with ''${status}" >&2
                  fi
                fi

                if command -v input-branches-push-force >/dev/null 2>&1; then
                  input-branches-push-force || true
                fi

                git add -u inputs || true

                echo "==> Refreshing flake.lock for vendored inputs"
                lock_args=()
                while IFS= read -r path; do
                  case "''${path}" in
                    inputs/*)
                      lock_args+=("--update-input" "''${path##*/}")
                      ;;
                    *) ;;
                  esac
                done < <(git config --file .gitmodules --get-regexp "^submodule\\..*\\.path" | awk "{print \$2}")

                if [ "''${#lock_args[@]}" -gt 0 ]; then
                  if nix flake lock "''${lock_args[@]}"; then
                    git add flake.lock || true
                  else
                    echo "Warning: nix flake lock failed; leaving flake.lock untouched" >&2
                  fi
                fi

                if git diff --cached --quiet -- inputs flake.lock; then
                  echo "No input bumps to commit."
                else
                  git -c core.hooksPath=/dev/null commit --no-verify -m "chore(inputs): bump vendored inputs" -- inputs flake.lock
                fi

                if [ ''${status} -ne 0 ]; then
                  exit ''${status}
                fi
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
            ripgrep
            pre-commit
            age
            sops
            ssh-to-age
            ssh-to-pgp
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
