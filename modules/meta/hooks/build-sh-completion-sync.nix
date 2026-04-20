_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-build-sh-completion-sync = pkgs.writeShellApplication {
        name = "hook-build-sh-completion-sync";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            script="build.sh"
            module="modules/apps/build-sh-completion.nix"

            if [ ! -f "$script" ]; then
              echo "✗ $script not found" >&2
              exit 1
            fi
            if [ ! -f "$module" ]; then
              echo "✗ $module not found" >&2
              exit 1
            fi

            # Extract long flags from build.sh case patterns.
            # Matches "  -x | --flag)" and "  --flag)" but skips "--)" and "*)".
            mapfile -t script_flags < <(
              grep -E '^[[:space:]]*(-[a-zA-Z][[:space:]]*\|[[:space:]]*)?--[a-zA-Z][a-zA-Z-]*\)' "$script" \
                | grep -oE -- '--[a-zA-Z][a-zA-Z-]*' \
                | sort -u
            )

            # Extract long flags from the _arguments block in the completion module.
            # Only lines starting with a single-quote (the zsh _arguments spec format).
            mapfile -t module_flags < <(
              grep -E "^[[:space:]]*'(\(|-[a-zA-Z]|--)" "$module" \
                | grep -oE -- '--[a-zA-Z][a-zA-Z-]*' \
                | sort -u
            )

            declare -A script_map=()
            for f in "''${script_flags[@]}"; do script_map["$f"]=1; done

            declare -A module_map=()
            for f in "''${module_flags[@]}"; do module_map["$f"]=1; done

            declare -a missing=()
            for f in "''${script_flags[@]}"; do
              if [ -z "''${module_map[$f]:-}" ]; then
                missing+=("$f")
              fi
            done

            declare -a stale=()
            for f in "''${module_flags[@]}"; do
              if [ -z "''${script_map[$f]:-}" ]; then
                stale+=("$f")
              fi
            done

            if [ "''${#missing[@]}" -eq 0 ] && [ "''${#stale[@]}" -eq 0 ]; then
              exit 0
            fi

            echo "" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "❌ Error: $module is out of sync with $script" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2

            if [ "''${#missing[@]}" -gt 0 ]; then
              echo "📝 Missing in completion (add _arguments entries in $module):" >&2
              for f in "''${missing[@]}"; do
                echo "   $f" >&2
              done
              echo "" >&2
            fi

            if [ "''${#stale[@]}" -gt 0 ]; then
              echo "🗑️  Stale in completion (remove _arguments entries from $module):" >&2
              for f in "''${stale[@]}"; do
                echo "   $f" >&2
              done
              echo "" >&2
            fi

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "ℹ️  Summary:" >&2
            echo "   Script flags:     ''${#script_flags[@]}" >&2
            echo "   Completion flags: ''${#module_flags[@]}" >&2
            echo "   Missing:          ''${#missing[@]}" >&2
            echo "   Stale:            ''${#stale[@]}" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            exit 1
          '';
      };
    };
}
