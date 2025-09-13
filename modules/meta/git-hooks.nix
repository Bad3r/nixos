{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    {
      pre-commit = {
        check.enable = true;
        settings = {
          hooks = {
            # Nix-specific hooks
            nixfmt-rfc-style = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };
            # Avoid scanning vendored inputs and large local docs
            deadnix = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };
            statix =
              let
                statixWrapper = pkgs.writeShellApplication {
                  name = "statix-precommit-wrapper";
                  runtimeInputs = [
                    pkgs.statix
                    pkgs.coreutils
                  ];
                  text = ''
                    set -euo pipefail
                    status=0
                    if [ "$#" -eq 0 ]; then
                      # Fallback to repository root
                      statix check --format errfmt || status=$?
                      exit $status
                    fi
                    for f in "$@"; do
                      # Only run on existing files
                      if [ -f "$f" ]; then
                        statix check --format errfmt -- "$f" || status=$?
                      fi
                    done
                    exit $status
                  '';
                };
              in
              {
                enable = true;
                excludes = [
                  "^inputs/"
                  "^nixos_docs_md/"
                ];
                entry = "${statixWrapper}/bin/statix-precommit-wrapper";
                pass_filenames = true;
              };
            # flake-checker not used: we rely on
            # `nix flake check` and pre-push submodule checks

            # Shell script quality
            shellcheck = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };

            # Documentation and text quality
            typos =
              let
                typosConfig = pkgs.writeText "typos.toml" ''
                  [default.extend-words]
                  facter = "facter"
                  hda = "hda"
                  importas = "importas"
                  Hime = "Hime"
                  hime = "hime"
                  Mosquitto = "Mosquitto"
                  mosquitto = "mosquitto"
                  MUC = "MUC"
                  muc = "muc"
                  crypted = "crypted"
                  browseable = "browseable"
                  resolveable = "resolveable"

                  [files]
                  extend-exclude = [
                      "nixos_docs_md/*.md",
                      "flake.lock",
                      ".clj-kondo/**",
                      "**/.clj-kondo/**",
                      ".lsp/**",
                      "**/.lsp/**",
                  ]
                '';
              in
              {
                enable = true;
                # Keep hook-level excludes lightweight; config handles deep ignores
                excludes = [
                  "^inputs/"
                  "^nixos_docs_md/"
                ];
                entry = "${pkgs.typos}/bin/typos --config ${typosConfig}";
                pass_filenames = true;
              };
            trim-trailing-whitespace = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };

            # Security
            detect-private-keys = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };
            ripsecrets = {
              enable = true;
              excludes = [
                "nixos_docs_md/.*\\.md$" # Documentation files with examples
                "modules/networking/networking.nix" # Contains public minisign key
                "^inputs/"
              ];
            };

            # Config file validation
            check-yaml = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };
            check-json = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };

            # Enforce that files in secret paths are SOPS-encrypted
            ensure-sops = {
              enable = true;
              name = "ensure-sops";
              entry = "${pkgs.pre-commit-hook-ensure-sops}/bin/pre-commit-hook-ensure-sops";
              pass_filenames = true;
              # Limit to common secret file types under the secrets/ directory
              files = "^secrets/.*\\.(yaml|yml|json|env|ini)$";
            };

            # Managed files drift check (via files writer)
            managed-files-drift =
              let
                driftChecker = pkgs.writeShellApplication {
                  name = "check-managed-files-drift";
                  runtimeInputs = [
                    pkgs.git
                    pkgs.coreutils
                    pkgs.diffutils
                    pkgs.gnugrep
                    pkgs.gawk
                  ];
                  text = ''
                    set -euo pipefail
                    root=$(git rev-parse --show-toplevel)
                    cd "$root"
                    if ! command -v write-files >/dev/null 2>&1; then
                      # Silent success when the writer is unavailable
                      exit 0
                    fi
                    writer=$(command -v write-files)
                    # Parse pairs of (store source -> destination) from the writer script
                    # Lines look like: cat /nix/store/...-NAME > path
                    mapfile -t pairs < <(grep -E '^cat /nix/store/.+ > .+$' "$writer" || true)
                    if [ "''${#pairs[@]}" -eq 0 ]; then
                      # No managed files declared; nothing to check
                      exit 0
                    fi
                    drift=0
                    AUTO_FIX="''${AUTO_FIX_MANAGED:-1}"
                    VERBOSE="''${MANAGED_FILES_VERBOSE:-0}"
                    declare -a update_paths=()
                    for line in "''${pairs[@]}"; do
                      src=$(printf '%s' "$line" | awk '{print $2}')
                      # take everything after the '>' and trim spaces
                      dst_rel=$(printf '%s' "$line" | sed -E 's/^.*>\s*//')
                      dst="$root/$dst_rel"
                      if [ ! -f "$dst" ]; then
                        if [ "$AUTO_FIX" != 1 ] || [ "$VERBOSE" = 1 ]; then
                          echo "✗ Missing managed file: $dst_rel" >&2
                        fi
                        drift=1
                        update_paths+=("$dst_rel")
                        continue
                      fi
                      if ! cmp -s "$src" "$dst"; then
                        if [ "$AUTO_FIX" != 1 ] || [ "$VERBOSE" = 1 ]; then
                          echo "✗ Drift detected: $dst_rel" >&2
                          # Show a short diff context for readability (non-fatal)
                          diff -u --label "$dst_rel(expected)" "$src" --label "$dst_rel" "$dst" | sed 's/^/    /' || true
                        fi
                        drift=1
                        update_paths+=("$dst_rel")
                      fi
                    done
                    if [ "$drift" -ne 0 ]; then
                      # Auto-fix managed files, stage, and commit them.
                      # Guard recursion and hooks.
                      if [ "''${#update_paths[@]}" -gt 0 ]; then
                        write-files >/dev/null
                        # Re-stage only the paths that were out-of-date
                        git add -- "''${update_paths[@]}" 2>/dev/null || true
                        if [ "$AUTO_FIX" = 1 ]; then
                          # Create a focused commit containing only the managed files that changed
                          GIT_COMMITTER_DATE="$(date -u -R)" \
                          GIT_AUTHOR_DATE="$(date -u -R)" \
                          git -c core.hooksPath=/dev/null commit --no-verify \
                            -m "chore(managed): refresh generated files" -- "''${update_paths[@]}" >/dev/null 2>&1 || true
                        else
                          if [ "$VERBOSE" = 1 ]; then
                            echo "Run: write-files, then commit the changes." >&2
                          fi
                          exit 1
                        fi
                      fi
                      # Report success to allow the user's commit to proceed
                      exit 0
                    fi
                  '';
                };
              in
              {
                enable = true;
                name = "managed-files-drift";
                entry = lib.getExe driftChecker;
                pass_filenames = false;
                always_run = true;
                verbose = false;
              };
          };

          # Enforce: forbid `with config.flake.nixosModules.apps;` usage in roles
          forbid-with-apps-in-roles =
            let
              checker = pkgs.writeShellApplication {
                name = "forbid-with-apps-in-roles";
                runtimeInputs = [
                  pkgs.ripgrep
                  pkgs.gnugrep
                  pkgs.coreutils
                ];
                text = ''
                  set -euo pipefail
                  cd "$(git rev-parse --show-toplevel)"
                  PATTERN='with\s+config\.flake\.nixosModules\.apps\s*;'
                  # Prefer ripgrep if available
                  if command -v rg >/dev/null 2>&1; then
                    if rg -n -S -e "$PATTERN" --glob '*.nix' modules/roles >/dev/null; then
                      echo "✗ Forbidden usage: 'with config.flake.nixosModules.apps;' found in modules/roles/*.nix" >&2
                      echo "  Use helpers: config.flake.lib.nixos.getApp/getApps with explicit string names." >&2
                      echo "  See docs/RFC-001.md for guidance." >&2
                      rg -n -S -e "$PATTERN" --glob '*.nix' modules/roles || true
                      exit 1
                    fi
                  else
                    if grep -R -n -E "$PATTERN" --include='*.nix' modules/roles >/dev/null 2>&1; then
                      echo "✗ Forbidden usage: 'with config.flake.nixosModules.apps;' found in modules/roles/*.nix" >&2
                      echo "  Use helpers: config.flake.lib.nixos.getApp/getApps with explicit string names." >&2
                      echo "  See docs/RFC-001.md for guidance." >&2
                      grep -R -n -E "$PATTERN" --include='*.nix' modules/roles || true
                      exit 1
                    fi
                  fi
                '';
              };
            in
            {
              enable = true;
              name = "forbid-with-apps-in-roles";
              entry = lib.getExe checker;
              pass_filenames = false;
              always_run = true;
              verbose = true;
            };
        };
      };
    };
}
