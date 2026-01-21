_: {
  perSystem =
    { pkgs, config, ... }:
    {
      packages.lefthook-treefmt = pkgs.writeShellApplication {
        name = "lefthook-treefmt";
        runtimeInputs = [
          config.treefmt.build.wrapper
          pkgs.git
          pkgs.coreutils
          pkgs.util-linux # flock
        ];
        text = # bash
          ''
            # Caching and locking for treefmt
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

            # Get ALL modified files (staged + unstaged), excluding symlinks to nix store
            # This ensures consistency - format everything that's changed from HEAD
            mapfile -t modified < <(git diff HEAD --name-only --diff-filter=ACM | while read -r f; do
              if [ -L "$f" ]; then
                target=$(readlink -f "$f" 2>/dev/null || true)
                case "$target" in /nix/store/*) continue ;; esac
              fi
              printf '%s\n' "$f"
            done)

            if [ "''${#modified[@]}" -eq 0 ]; then
              exit 0
            fi

            err_file=$(mktemp)
            trap 'rm -f "$err_file"; flock -u 9' EXIT

            if ! treefmt "''${modified[@]}" >/dev/null 2>"$err_file"; then
              echo "treefmt: formatting failed - manual fix required:" >&2
              cat "$err_file" >&2
              exit 1
            fi
          '';
      };
    };
}
