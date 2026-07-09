_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-nix-parse = pkgs.writeShellApplication {
        name = "hook-nix-parse";
        runtimeInputs = [
          # Lix: parse semantics must match what hosts run (RFC #282).
          pkgs.lixPackageSets.latest.lix
          pkgs.coreutils
        ];
        text = # bash
          ''
            set -euo pipefail

            status=0
            if [ "$#" -eq 0 ]; then
              exit 0
            fi

            for path in "$@"; do
              if [ -f "$path" ]; then
                # Suppress parsed output, but keep parse errors on stderr.
                # pipe-operator is passed explicitly so the hook does not
                # depend on the invoking host's nix.conf feature list.
                nix-instantiate --extra-experimental-features pipe-operator \
                  --parse "$path" 1>/dev/null || status=$?
              fi
            done

            exit "$status"
          '';
      };
    };
}
