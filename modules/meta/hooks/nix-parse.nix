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
                nix-instantiate --parse "$path" >/dev/null || status=$?
              fi
            done

            exit "$status"
          '';
      };
    };
}
