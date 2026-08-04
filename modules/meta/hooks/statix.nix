/*
  Hook: statix

  Also exposed as a flake check over the whole tree. The pre-commit hook only
  ever sees staged files, and nothing in .github/workflows/check.yml runs
  statix, so a lint in a file nobody stages again was reachable on main
  indefinitely. The check runs the hook's own binary rather than a second
  invocation of its own, so CI and pre-commit cannot drift apart.
*/
_: {
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      packages.hook-statix = pkgs.writeShellApplication {
        name = "hook-statix";
        runtimeInputs = [
          pkgs.statix
          pkgs.coreutils
        ];
        text = # bash
          ''
            set -euo pipefail

            status=0
            if [ "$#" -eq 0 ]; then
              statix check --format errfmt || status=$?
              exit "$status"
            fi

            for path in "$@"; do
              if [ -f "$path" ]; then
                statix check --format errfmt "$path" || status=$?
              fi
            done
            exit "$status"
          '';
      };

      # Only the .nix files: statix reads nothing else, and narrowing the
      # source keeps this off the rebuild path of every unrelated commit.
      checks.statix-tree =
        let
          nixSources = lib.fileset.toSource {
            root = ../../..;
            # docs/nixos-manual/ is an upstream mirror synced by
            # scripts/update-nixos-manual.sh, excluded by ../pre-commit.nix and
            # ../treefmt.nix for that reason. Scanning it here would fail CI on
            # code this repo cannot fix without diverging from upstream, and
            # would be the scope drift between hook and check this file exists
            # to remove.
            fileset = lib.fileset.difference (lib.fileset.fileFilter (
              file: file.hasExt "nix"
            ) ../../..) ../../../docs/nixos-manual;
          };
        in
        pkgs.runCommand "statix-tree-check"
          {
            # Opts this check into the runtime build step in
            # .github/workflows/check.yml, which otherwise only forces drvPaths.
            passthru.runtimeCheck = true;
            nativeBuildInputs = [ config.packages.hook-statix ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            # Planted before the tree is trusted, the way ../build-time-shell.nix
            # plants its own fixture: nothing else calls hook-statix without
            # arguments (../pre-commit.nix sets pass_filenames), so a clean $out
            # here would otherwise be indistinguishable from a run that walked
            # nothing.
            planted="$PWD/planted"
            mkdir -p "$planted"
            # W02, an empty let-in.
            printf 'let in 1\n' >"$planted/fixture.nix"
            if (cd "$planted" && hook-statix); then
              echo "statix-tree: hook-statix reported nothing on a planted lint, so the tree scan below would pass regardless" >&2
              exit 1
            fi

            cd ${nixSources}
            hook-statix
            echo "statix reported nothing across the tree" >"$out"
          '';
    };
}
