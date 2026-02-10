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
            root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
            cd "$root"

            apps_dir="modules/apps"
            catalog_file="modules/system76/apps-enable.nix"

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

            mapfile -t catalog_apps < <(
              grep -E '\.extended\.enable' "$catalog_file" \
                | sed -E 's/^\s+//' \
                | sed -E "s/^([\"']?)([a-zA-Z0-9_-]+)\1\.extended\.enable.*/\2/" \
                | sort
            )

            declare -A fs_map catalog_map
            for app in "''${filesystem_apps[@]}"; do
              fs_map["$app"]=1
            done
            for app in "''${catalog_apps[@]}"; do
              catalog_map["$app"]=1
            done

            declare -a missing=()
            for app in "''${filesystem_apps[@]}"; do
              if [ -z "''${catalog_map[$app]:-}" ]; then
                missing+=("$app")
              fi
            done

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
          '';
      };
    };
}
