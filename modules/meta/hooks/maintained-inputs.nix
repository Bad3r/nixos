_: {
  # The hook body lives in scripts/check-maintained-inputs.sh rather than inline
  # so the validator can be invoked and shellcheck-tested directly from a
  # checkout, and so tests under tests/check-maintained-inputs/ can run the
  # same source file without going through Nix evaluation.
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-maintained-inputs = pkgs.writeShellApplication {
        name = "hook-maintained-inputs";
        runtimeInputs = [
          pkgs.bash
          pkgs.git
          pkgs.nix
          pkgs.jq
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
        ];
        text = # bash
          ''
            exec bash ${../../../scripts/check-maintained-inputs.sh} "$@"
          '';
      };
    };
}
