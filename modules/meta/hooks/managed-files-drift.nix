_: {
  perSystem =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      packages.hook-managed-files-drift = pkgs.writeShellApplication {
        name = "hook-managed-files-drift";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.diffutils
          pkgs.jq
          pkgs.gnused
          config.files.writer.drv
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            mode="''${MANAGED_FILES_MODE:-verify}"
            verbose="''${MANAGED_FILES_VERBOSE:-0}"
            writer="${config.files.writer.drv}/bin/${config.files.writer.exeFilename}"
            # Authoritative manifest (list of {path, source}) rendered from the
            # same files.file config the writer consumes. Reading it directly
            # keeps this hook independent of the writer script's emitted shape.
            manifest="${config.files.writer.filesJson}"

            if ! manifest_lines=$(jq -r '.[] | "\(.source)\t\(.path)"' "$manifest"); then
              echo "✗ Failed to read manifest (jq error): $manifest" >&2
              exit 1
            fi
            mapfile -t pairs < <(printf '%s' "$manifest_lines")
            # This repo always manages a non-empty artifact set; zero parsed
            # entries means the files-input manifest shape changed. Fail closed
            # instead of reporting a vacuous pass with nothing verified.
            if [ "''${#pairs[@]}" -eq 0 ]; then
              echo "✗ No managed files parsed from files.json manifest: $manifest" >&2
              echo "  The files input changed its manifest shape; update hook-managed-files-drift." >&2
              exit 1
            fi

            # A manifest that parses but silently drops entries must still fail
            # closed instead of verifying a partial set. Pin coverage to the
            # files actually declared in Nix (same config.files.file read as
            # modules/files.nix:63), not just a non-empty parsed count.
            expected=(${lib.escapeShellArgs (builtins.attrNames config.files.file)})
            for want in "''${expected[@]}"; do
              found=0
              for line in "''${pairs[@]}"; do
                if [ "''${line#*$'\t'}" = "$want" ]; then
                  found=1
                  break
                fi
              done
              if [ "$found" -eq 0 ]; then
                echo "✗ Declared managed file absent from manifest: $want" >&2
                echo "  The files input manifest no longer covers every files.file entry." >&2
                exit 1
              fi
            done

            drift=0
            declare -a update_paths=()

            for line in "''${pairs[@]}"; do
              src=''${line%%$'\t'*}
              dst_rel=''${line#*$'\t'}

              if [ -z "$src" ] || [ -z "$dst_rel" ] || [ "$src" = "null" ] \
                || [ "$dst_rel" = "null" ] || [ ! -e "$src" ]; then
                echo "✗ Unparsable manifest entry (source/path missing): $line" >&2
                exit 1
              fi

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
