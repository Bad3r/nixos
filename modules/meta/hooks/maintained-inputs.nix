_: {
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
