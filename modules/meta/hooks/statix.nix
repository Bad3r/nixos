_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.lefthook-statix = pkgs.writeShellApplication {
        name = "lefthook-statix";
        runtimeInputs = [
          pkgs.statix
          pkgs.coreutils
        ];
        text = # bash
          ''
            status=0
            if [ "$#" -eq 0 ]; then
              statix check --format errfmt || status=$?
              exit $status
            fi
            for f in "$@"; do
              if [ -f "$f" ]; then
                statix check --format errfmt "$f" || status=$?
              fi
            done
            exit $status
          '';
      };
    };
}
