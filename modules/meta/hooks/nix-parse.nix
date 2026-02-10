_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-nix-parse = pkgs.writeShellApplication {
        name = "hook-nix-parse";
        runtimeInputs = [
          pkgs.nix
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
                nix-instantiate --parse "$path" 1>/dev/null || status=$?
              fi
            done

            exit "$status"
          '';
      };
    };
}
