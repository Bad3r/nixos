_: {
  perSystem =
    { pkgs, config, ... }:
    {
      packages.hook-managed-files-drift = pkgs.writeShellApplication {
        name = "hook-managed-files-drift";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.diffutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
          config.files.writer.drv
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            mode="''${MANAGED_FILES_MODE:-verify}"
            verbose="''${MANAGED_FILES_VERBOSE:-0}"
            writer="${config.files.writer.drv}/bin/write-files"

            mapfile -t pairs < <(grep -E '^cat /nix/store/.+ > .+$' "$writer" || true)
            if [ "''${#pairs[@]}" -eq 0 ]; then
              exit 0
            fi

            drift=0
            declare -a update_paths=()

            for line in "''${pairs[@]}"; do
              src=$(printf '%s' "$line" | awk '{print $2}')
              dst_rel=$(printf '%s' "$line" | sed -E 's/^.*>\s*//')
              dst="$root/$dst_rel"

              if [ ! -f "$dst" ]; then
                drift=1
                update_paths+=("$dst_rel")
                echo "✗ Missing managed file: $dst_rel" >&2
                continue
              fi

              if ! cmp -s "$src" "$dst"; then
                drift=1
                update_paths+=("$dst_rel")
                echo "✗ Drift detected: $dst_rel" >&2
                if [ "$verbose" = "1" ]; then
                  diff -u --label "$dst_rel(expected)" "$src" --label "$dst_rel" "$dst" \
                    | sed 's/^/    /' || true
                fi
              fi
            done

            if [ "$drift" -eq 0 ]; then
              exit 0
            fi

            if [ "$mode" = "apply" ]; then
              "$writer" >/dev/null
              git add "''${update_paths[@]}" 2>/dev/null || true
              echo "Managed files refreshed and staged:"
              printf '  - %s\n' "''${update_paths[@]}"
              exit 0
            fi

            echo "" >&2
            echo "Managed files out of sync with Nix definitions." >&2
            echo "Run: nix develop -c write-files" >&2
            echo "Then stage updates and commit normally." >&2
            exit 1
          '';
      };
    };
}
