{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      pre-commit = {
        check.enable = true;
        settings = {
          hooks = {
            # Nix-specific hooks
            nixfmt-rfc-style =
              let
                nixfmtAutostage = pkgs.writeShellApplication {
                  name = "nixfmt-precommit-autostage";
                  runtimeInputs = [
                    pkgs.nixfmt-rfc-style
                    pkgs.git
                    pkgs.coreutils
                  ];
                  text = ''
                    set -euo pipefail
                    if [ "$#" -eq 0 ]; then
                      exit 0
                    fi

                    for f in "$@"; do
                      if [ -f "$f" ]; then
                        nixfmt -- "$f"
                        if ! git diff --quiet -- "$f"; then
                          git add -- "$f"
                          printf "nixfmt: auto-formatted %s\\n" "$f" >&2
                        fi
                      fi
                    done
                  '';
                };
              in
              {
                enable = true;
                excludes = [
                  "^inputs/"
                  "^nixos_docs_md/"
                ];
                entry = lib.getExe nixfmtAutostage;
                pass_filenames = true;
              };
            treefmt =
              let
                treefmtAutostage = pkgs.writeShellApplication {
                  name = "treefmt-precommit-autostage";
                  runtimeInputs = [
                    config.treefmt.build.wrapper
                    pkgs.git
                    pkgs.coreutils
                    pkgs.util-linux
                  ];
                  text = ''
                    set -euo pipefail

                    cache_root="''${TREEFMT_CACHE_ROOT:-$PWD/.git/treefmt-cache}"
                    if ! mkdir -p "''${cache_root}" 2>/dev/null; then
                      cache_root="''${TMPDIR:-/tmp}/treefmt-cache"
                      mkdir -p "''${cache_root}"
                    fi

                    cache_home="''${cache_root}/cache"
                    mkdir -p "''${cache_home}"

                    lock_file="''${cache_root}/cache.lock"
                    lock_timeout="''${TREEFMT_CACHE_TIMEOUT:-30}"

                    exec 9>"''${lock_file}"
                    if ! flock -w "''${lock_timeout}" 9; then
                      echo "treefmt: failed to acquire cache lock within ''${lock_timeout}s" >&2
                      exit 1
                    fi
                    trap 'flock -u 9' EXIT

                    export TREEFMT_CACHE_DB="''${cache_home}/eval-cache"

                    if [ "$#" -gt 0 ]; then
                      treefmt "$@"
                      mapfile -t targets < <(printf "%s\n" "$@")
                    else
                      treefmt
                      mapfile -t targets < <(git diff --name-only --diff-filter=ACM)
                    fi

                    if [ "''${#targets[@]}" -gt 0 ]; then
                      for file in "''${targets[@]}"; do
                        if [ -n "$file" ] && [ -e "$file" ] && ! git diff --quiet -- "$file"; then
                          git add -- "$file"
                          printf "treefmt: auto-formatted %s\\n" "$file" >&2
                        fi
                      done
                    fi
                  '';
                };
              in
              {
                enable = true;
                excludes = [
                  "^inputs/"
                  "^nixos_docs_md/"
                ];
                pass_filenames = true;
                entry = lib.getExe treefmtAutostage;
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
                  "80CA80DA06B77EE708D57D9B5B92AB136C03BA48" = "80CA80DA06B77EE708D57D9B5B92AB136C03BA48"

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
              # Restrict to pre-commit only; avoid pre-push stage
              stages = [
                "pre-commit"
                "manual"
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
              # Align with example policy: include structured and binary encrypted secret formats
              files = "^secrets/.*\\.(yaml|yml|json|env|ini|age|enc)$";
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

            # Verify apps-enable.nix is synchronized with modules/apps/
            apps-catalog-sync =
              let
                syncChecker = pkgs.writeShellApplication {
                  name = "check-apps-catalog-sync";
                  runtimeInputs = [
                    pkgs.git
                    pkgs.coreutils
                    pkgs.gnugrep
                    pkgs.gnused
                    pkgs.gawk
                    pkgs.findutils
                  ];
                  text = ''
                    set -euo pipefail

                    root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
                    cd "$root"

                    apps_dir="modules/apps"
                    catalog_file="modules/system76/apps-enable.nix"

                    # Apps intentionally excluded from catalog (managed by specialized modules)
                    # These apps are controlled by domain-specific modules, not apps-enable.nix
                    excluded_apps=(
                      "qemu"                # Controlled by virtualization.nix
                      "vmware-workstation"  # Controlled by virtualization.nix
                      "ovftool"             # Controlled by virtualization.nix
                    )

                    # Check if this hook should run by examining staged changes
                    # Only run if modules/apps/ or apps-enable.nix are affected
                    should_run=0

                    # Check for added/deleted files in modules/apps/
                    if git diff --cached --name-status --diff-filter=AD | grep -q "^[AD].*$apps_dir/.*\.nix$"; then
                      should_run=1
                    fi

                    # Check if apps-enable.nix was modified
                    if git diff --cached --name-only | grep -q "^$catalog_file$"; then
                      should_run=1
                    fi

                    # Exit early if not triggered
                    if [ "$should_run" -eq 0 ]; then
                      exit 0
                    fi

                    # Extract app names from modules/apps/ (exclude _*.nix files)
                    mapfile -t filesystem_apps < <(
                      find "$apps_dir" -maxdepth 1 -type f -name "*.nix" ! -name "_*.nix" -printf "%f\n" \
                        | sed 's/\.nix$//' \
                        | sort
                    )

                    # Filter out excluded apps from filesystem list
                    declare -A excluded_map
                    for excluded in "''${excluded_apps[@]}"; do
                      excluded_map["$excluded"]=1
                    done

                    declare -a filtered_fs_apps=()
                    for app in "''${filesystem_apps[@]}"; do
                      if [ -z "''${excluded_map[$app]:-}" ]; then
                        filtered_fs_apps+=("$app")
                      fi
                    done
                    filesystem_apps=("''${filtered_fs_apps[@]}")

                    # Extract app names from apps-enable.nix
                    # Parse lines like: "app-name".extended.enable or app.extended.enable
                    mapfile -t catalog_apps < <(
                      grep -E '\.extended\.enable' "$catalog_file" \
                        | sed -E 's/^\s+//' \
                        | sed -E 's/^(["\047]?)([a-zA-Z0-9_-]+)\1\.extended\.enable.*/\2/' \
                        | sort
                    )

                    # Convert arrays to associative arrays for efficient lookups
                    declare -A fs_map catalog_map

                    for app in "''${filesystem_apps[@]}"; do
                      fs_map["$app"]=1
                    done

                    for app in "''${catalog_apps[@]}"; do
                      catalog_map["$app"]=1
                    done

                    # Find missing entries (in filesystem but not in catalog)
                    declare -a missing=()
                    for app in "''${filesystem_apps[@]}"; do
                      if [ -z "''${catalog_map[$app]:-}" ]; then
                        missing+=("$app")
                      fi
                    done

                    # Find stale entries (in catalog but not in filesystem)
                    declare -a stale=()
                    for app in "''${catalog_apps[@]}"; do
                      if [ -z "''${fs_map[$app]:-}" ]; then
                        stale+=("$app")
                      fi
                    done

                    # Report errors if any discrepancies found
                    if [ "''${#missing[@]}" -gt 0 ] || [ "''${#stale[@]}" -gt 0 ]; then
                      echo "" >&2
                      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                      echo "❌ Error: apps-enable.nix is out of sync with modules/apps/" >&2
                      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                      echo "" >&2

                      if [ "''${#missing[@]}" -gt 0 ]; then
                        echo "📝 Missing entries (add these to $catalog_file):" >&2
                        echo "" >&2
                        for app in "''${missing[@]}"; do
                          # Determine if quoting is needed (contains hyphens)
                          if [[ "$app" =~ - ]]; then
                            echo "  \"$app\".extended.enable = lib.mkOverride 1100 false;" >&2
                          else
                            echo "  $app.extended.enable = lib.mkOverride 1100 false;" >&2
                          fi
                        done
                        echo "" >&2
                      fi

                      if [ "''${#stale[@]}" -gt 0 ]; then
                        echo "🗑️  Stale entries (remove these from $catalog_file):" >&2
                        echo "" >&2
                        for app in "''${stale[@]}"; do
                          # Find line number for helpful context
                          if [[ "$app" =~ - ]]; then
                            line_num=$(grep -n "\"$app\"\.extended\.enable" "$catalog_file" | cut -d: -f1 || echo "?")
                          else
                            line_num=$(grep -n "$app\.extended\.enable" "$catalog_file" | cut -d: -f1 || echo "?")
                          fi
                          echo "  $app (line $line_num)" >&2
                        done
                        echo "" >&2
                      fi

                      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                      echo "ℹ️  Summary:" >&2
                      echo "   Filesystem: ''${#filesystem_apps[@]} apps" >&2
                      echo "   Catalog:    ''${#catalog_apps[@]} apps" >&2
                      echo "   Missing:    ''${#missing[@]} entries" >&2
                      echo "   Stale:      ''${#stale[@]} entries" >&2
                      if [ "''${#excluded_apps[@]}" -gt 0 ]; then
                        echo "   Excluded:   ''${#excluded_apps[@]} apps (managed by specialized modules)" >&2
                      fi
                      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                      echo "" >&2
                      exit 1
                    fi

                    # Success - everything is synchronized
                    exit 0
                  '';
                };
              in
              {
                enable = true;
                name = "apps-catalog-sync";
                entry = lib.getExe syncChecker;
                pass_filenames = false;
                stages = [
                  "pre-commit"
                  "manual"
                ];
              };
          };
        };
      };
    };
}
