_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.lefthook-managed-files-drift = pkgs.writeShellApplication {
        name = "lefthook-managed-files-drift";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.diffutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
        ];
        text = # bash
          ''
            root=$(git rev-parse --show-toplevel)
            cd "$root"

            if ! command -v write-files >/dev/null 2>&1; then
              exit 0
            fi

            writer=$(command -v write-files)
            mapfile -t pairs < <(grep -E '^cat /nix/store/.+ > .+$' "$writer" || true)

            if [ "''${#pairs[@]}" -eq 0 ]; then
              exit 0
            fi

            drift=0
            AUTO_FIX="''${AUTO_FIX_MANAGED:-1}"
            VERBOSE="''${MANAGED_FILES_VERBOSE:-0}"
            declare -a update_paths=()

            for line in "''${pairs[@]}"; do
              src=$(printf '%s' "$line" | awk '{print $2}')
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
                  diff -u --label "$dst_rel(expected)" "$src" --label "$dst_rel" "$dst" | sed 's/^/    /' || true
                fi
                drift=1
                update_paths+=("$dst_rel")
              fi
            done

            if [ "$drift" -ne 0 ]; then
              if [ "''${#update_paths[@]}" -gt 0 ]; then
                write-files >/dev/null
                git add "''${update_paths[@]}" 2>/dev/null || true

                if [ "$AUTO_FIX" = 1 ]; then
                  GIT_COMMITTER_DATE="$(date -u -R)" \
                  GIT_AUTHOR_DATE="$(date -u -R)" \
                  git -c core.hooksPath=/dev/null commit --no-verify \
                    -m "chore(managed): refresh generated files" "''${update_paths[@]}" >/dev/null 2>&1 || true
                else
                  if [ "$VERBOSE" = 1 ]; then
                    echo "Run: write-files, then commit the changes." >&2
                  fi
                  exit 1
                fi
              fi
              exit 0
            fi
          '';
      };
    };
}
