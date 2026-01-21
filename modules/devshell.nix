{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.make-shell.flakeModules.default
    ./devshell/pentesting.nix
  ];
  perSystem =
    { pkgs, config, ... }:
    {
      # Use make-shells pattern for better modularity
      make-shells.default = {
        packages =
          with pkgs;
          let
            ghActionsRun = pkgs.writeShellApplication {
              name = "gh-actions-run";
              text = # bash
                ''
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
            nixfmt
            nil # Nix LSP
            nix-tree
            nix-diff
            zsh
            act
            jq
            yq
            ripgrep
            lefthook # Replaces pre-commit

            # Direct tools for inline lefthook commands
            deadnix # For: deadnix --fail {staged_files}
            statix # For: lefthook-statix (also available directly)
            typos # For: typos --config .typos.toml {staged_files}
            ripsecrets # For: ripsecrets {staged_files}
            yamllint # For: yamllint -d relaxed {staged_files}
            # jq already present for: jq empty {staged_files}

            # Lefthook hook scripts (from modules/meta/hooks/)
            config.packages."lefthook-treefmt"
            config.packages."lefthook-statix"
            config.packages."lefthook-ensure-sops"
            config.packages."lefthook-managed-files-drift"
            config.packages."lefthook-apps-catalog-sync"

            age
            sops
            ssh-to-age
            ssh-to-pgp
            ghActionsRun
            ghActionsList
            config.packages.generation-manager
            config.treefmt.build.wrapper
          ];

        shellHook = ''
          # Skip welcome message and interactive setup when generating lefthook cache
          if [ -z "''${LEFTHOOK_ENV:-}" ]; then
            echo "🚀 NixOS Configuration Development Shell"
            echo ""
            echo "Available commands:"
            echo "  nix flake check        - Validate the flake"
            echo "  nix fmt                - Format Nix files"
            echo "  lefthook install       - Install git hooks"
            echo "  lefthook run pre-commit - Run all pre-commit hooks"
            echo "  write-files            - Generate managed files (README.md, .actrc, .gitignore)"
            echo "  gh-actions-run [-n]    - Run all GitHub Actions locally (use -n for dry run)"
            echo "  gh-actions-list        - List discovered GitHub Actions jobs"
            echo ""

            # Use repo-local treefmt cache (matches lefthook hook location)
            treefmt_cache="$PWD/.git/treefmt-cache/cache"
            mkdir -p "$treefmt_cache" 2>/dev/null || true
            export TREEFMT_CACHE_DB="$treefmt_cache/eval-cache"

            lefthook install

            # Prefer zsh for interactive sessions
            if [ -n "''${PS1-}" ] && [ -z "''${ZSH_VERSION-}" ] && [ -t 1 ]; then
              export SHELL="${pkgs.zsh}/bin/zsh"
              exec "${pkgs.zsh}/bin/zsh" -l
            fi
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
