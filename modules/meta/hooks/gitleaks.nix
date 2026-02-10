_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-gitleaks = pkgs.writeShellApplication {
        name = "hook-gitleaks";
        runtimeInputs = [
          pkgs.gitleaks
          pkgs.git
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            args=(git --no-banner --redact)
            if [ -f ".gitleaks.toml" ]; then
              args+=(--config ".gitleaks.toml")
            fi
            if [ -f ".gitleaks-baseline.json" ]; then
              args+=(--baseline-path ".gitleaks-baseline.json")
            fi
            args+=(".")

            exec gitleaks "''${args[@]}"
          '';
      };
    };
}
