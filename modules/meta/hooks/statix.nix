_: {
  perSystem =
    { pkgs, ... }:
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
    };
}
