_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-apps-catalog-sync = pkgs.writeShellApplication {
        name = "hook-apps-catalog-sync";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
          pkgs.findutils
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            apps_dir="modules/apps"

            excluded_apps=(
              "qemu"
              "vmware-workstation"
              "ovftool"
            )

            mapfile -t filesystem_apps < <(
              find "$apps_dir" -maxdepth 1 -type f -name "*.nix" ! -name "_*.nix" -printf "%f\n" \
                | sed 's/\.nix$//' \
                | sort
            )

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

            declare -A fs_map=()
            for app in "''${filesystem_apps[@]}"; do
              fs_map["$app"]=1
            done

            # The common baseline at modules/hosts/common/apps-enable.nix is
            # the canonical catalog and must list every app from modules/apps/.
            # Per-host files (modules/<host>/apps-enable.nix) only carry
            # overrides for entries that diverge from the baseline; they are
            # not required to be complete and must only reference apps that
            # exist on the filesystem (stale-only check).
            common_catalog="modules/hosts/common/apps-enable.nix"

            add_all_catalog_files() {
              while IFS= read -r f; do
                catalog_files_to_check["$f"]=1
              done < <(
                {
                  echo "$common_catalog"
                  find . -path "*/modules/*/apps-enable.nix" -printf "%P\n"
                } | sort -u
              )
            }

            is_common_catalog() {
              [ "$1" = "$common_catalog" ]
            }

            # Determine which apps-enable.nix files to check.
            # In pre-push mode pre-commit sets PRE_COMMIT_FROM_REF / PRE_COMMIT_TO_REF.
            # App module changes affect every host catalog, so compare all catalogs in that case.
            # Catalog-only changes can stay scoped to the changed catalog files.
            # In manual mode those vars are absent so check every apps-enable.nix found.
            declare -A catalog_files_to_check=()

            from_ref="''${PRE_COMMIT_FROM_REF:-}"
            to_ref="''${PRE_COMMIT_TO_REF:-}"

            if [ -n "$from_ref" ] && [ -n "$to_ref" ]; then
              if [ "$from_ref" = "0000000000000000000000000000000000000000" ]; then
                if main_ref=$(git rev-parse origin/main 2>/dev/null); then
                  from_ref=$(git merge-base "$to_ref" "$main_ref" 2>/dev/null \
                    || git rev-list --max-parents=0 "$to_ref" | head -1)
                else
                  from_ref=$(git rev-list --max-parents=0 "$to_ref" | head -1)
                fi
              fi
              app_modules_changed=0
              while IFS= read -r changed_file; do
                if [[ "$changed_file" =~ ^modules/.+/apps-enable\.nix$ ]]; then
                  catalog_files_to_check["$changed_file"]=1
                elif [[ "$changed_file" =~ ^modules/apps/[^_/][^/]*\.nix$ ]]; then
                  app_modules_changed=1
                fi
              done < <(git diff --name-only "''${from_ref}..''${to_ref}" 2>/dev/null || true)
              if [ "$app_modules_changed" -eq 1 ]; then
                add_all_catalog_files
              elif [ "''${#catalog_files_to_check[@]}" -eq 0 ]; then
                exit 0
              fi
            else
              add_all_catalog_files
            fi

            overall_exit=0

            mapfile -t sorted_catalog_files < <(printf '%s\n' "''${!catalog_files_to_check[@]}" | sort)

            for catalog_file in "''${sorted_catalog_files[@]}"; do
              [ -f "$catalog_file" ] || continue

              # The common catalog enumerates entries as one
              # `name.extended.enable = ...;` line per app; per-host override
              # files express the same data as keys of a flat `appEnable`
              # attrset. The module routes entries to `programs` or `services`
              # by reading the common baseline namespace.
              # Pick the parser that matches the file shape so the stale check
              # actually runs for per-host files.
              if is_common_catalog "$catalog_file"; then
                mapfile -t catalog_apps < <(
                  grep -E '\.extended\.enable' "$catalog_file" \
                    | grep -v '^\s*#' \
                    | sed -E 's/^\s+//' \
                    | sed -E "s/^([\"']?)([a-zA-Z0-9_-]+)\1\.extended\.enable.*/\2/" \
                    | sort
                )
              else
                mapfile -t catalog_apps < <(
                  awk '
                    /^[[:space:]]*appEnable[[:space:]]*=[[:space:]]*\{/ { in_block=1; depth=1; next }
                    in_block {
                      n_open = gsub(/\{/, "&")
                      n_close = gsub(/\}/, "&")
                      depth += n_open - n_close
                      if (depth <= 0) { in_block=0; next }
                      if (depth == 1 && match($0, /^[[:space:]]+"?([A-Za-z0-9_.-]+)"?[[:space:]]*=[[:space:]]*(true|false)/, m)) { print m[1] }
                    }
                  ' "$catalog_file" | sort
                )
              fi

              declare -A catalog_map=()
              for app in "''${catalog_apps[@]}"; do
                catalog_map["$app"]=1
              done

              declare -a missing=()
              if is_common_catalog "$catalog_file"; then
                for app in "''${filesystem_apps[@]}"; do
                  if [ -z "''${catalog_map[$app]:-}" ]; then
                    missing+=("$app")
                  fi
                done
              fi

              declare -a stale=()
              for app in "''${catalog_apps[@]}"; do
                if [ -z "''${fs_map[$app]:-}" ]; then
                  stale+=("$app")
                fi
              done

              if [ "''${#missing[@]}" -gt 0 ] || [ "''${#stale[@]}" -gt 0 ]; then
                echo "" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "❌ Error: apps-enable.nix is out of sync with modules/apps/" >&2
                echo "   File: $catalog_file" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2

                if [ "''${#missing[@]}" -gt 0 ]; then
                  echo "📝 Missing entries (add these to $catalog_file):" >&2
                  echo "" >&2
                  for app in "''${missing[@]}"; do
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
                    if is_common_catalog "$catalog_file"; then
                      if [[ "$app" =~ - ]]; then
                        line_num=$(grep -n "\"$app\"\.extended\.enable" "$catalog_file" | cut -d: -f1 || echo "?")
                      else
                        line_num=$(grep -n "$app\.extended\.enable" "$catalog_file" | cut -d: -f1 || echo "?")
                      fi
                    else
                      if [[ "$app" =~ - ]]; then
                        line_num=$(grep -nE "^[[:space:]]+\"''${app}\"[[:space:]]*=[[:space:]]*(true|false)" "$catalog_file" | cut -d: -f1 || echo "?")
                      else
                        line_num=$(grep -nE "^[[:space:]]+''${app}[[:space:]]*=[[:space:]]*(true|false)" "$catalog_file" | cut -d: -f1 || echo "?")
                      fi
                    fi
                    echo "  $app (line $line_num)" >&2
                  done
                  echo "" >&2
                fi

                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "ℹ️  Summary:" >&2
                echo "   File:       $catalog_file" >&2
                echo "   Filesystem: ''${#filesystem_apps[@]} apps" >&2
                echo "   Catalog:    ''${#catalog_apps[@]} apps" >&2
                echo "   Missing:    ''${#missing[@]} entries" >&2
                echo "   Stale:      ''${#stale[@]} entries" >&2
                if [ "''${#excluded_apps[@]}" -gt 0 ]; then
                  echo "   Excluded:   ''${#excluded_apps[@]} apps (managed by specialized modules)" >&2
                fi
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2
                overall_exit=1
              fi
            done

            exit $overall_exit
          '';
      };
    };
}
