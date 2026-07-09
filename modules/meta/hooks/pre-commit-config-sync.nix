_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-pre-commit-config-sync = pkgs.writeShellApplication {
        name = "hook-pre-commit-config-sync";
        runtimeInputs = [
          pkgs.git
          # Lix: eval semantics must match what hosts run (RFC #282).
          pkgs.lixPackageSets.latest.lix
          pkgs.coreutils
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            # core.hooksPath points linked worktrees at the shared hooks
            # directory, matching the config resolution order used by the
            # installed pre-commit and pre-push scripts.
            hooks_dir=$(git rev-parse --path-format=absolute --git-path hooks)

            # Only files consumed by the in-flight pre-commit run force a
            # retry. Auxiliary hooks such as post-checkout are refreshed by
            # the same sync but never participate in the current commit.
            targets=(
              "$root/.pre-commit-config.yaml"
              "$hooks_dir/pre-commit-config.yaml"
              "$hooks_dir/pre-commit"
              "$hooks_dir/pre-push"
            )

            digest() {
              if [ -e "$1" ]; then
                sha256sum "$1" | cut -d' ' -f1
              else
                echo absent
              fi
            }

            declare -a before=()
            for target in "''${targets[@]}"; do
              before+=("$(digest "$target")")
            done

            # Re-entering the devshell runs the full existing sync pipeline:
            # the git-hooks.nix installation script, then
            # scripts/hooks/sync-pre-commit-hooks.sh and
            # scripts/hooks/install-git-hooks.sh from the shellHook.
            sync_log=$(mktemp -t pre-commit-config-sync.XXXXXX)
            # Features are passed explicitly so the hook does not depend on
            # the invoking host's nix.conf feature list.
            if ! nix develop --extra-experimental-features 'pipe-operator flake-self-attrs' \
              --accept-flake-config --offline -c true >"$sync_log" 2>&1; then
              {
                echo "pre-commit-config-sync: offline hook sync failed."
                echo "If updated inputs or tools are missing from the local store, realize them once with network access:"
                echo "  nix develop --accept-flake-config -c true"
                echo "then retry the commit."
                echo "--- nix output (tail; full log: $sync_log) ---"
                tail -n 40 "$sync_log"
              } >&2
              exit 1
            fi
            rm -f "$sync_log"

            changed=0
            for i in "''${!targets[@]}"; do
              if [ "$(digest "''${targets[$i]}")" != "''${before[$i]}" ]; then
                if [ "$changed" -eq 0 ]; then
                  echo "pre-commit-config-sync: generated hook state was stale for this commit:" >&2
                fi
                changed=1
                echo "  refreshed: ''${targets[$i]}" >&2
              fi
            done

            # The running pre-commit process already parsed the old config,
            # so continuing would validate this commit against stale hooks.
            if [ "$changed" -ne 0 ]; then
              echo "hooks were refreshed; retry commit." >&2
              exit 1
            fi
          '';
      };
    };
}
