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

            common=(--no-banner --redact)
            if [ -f ".gitleaks.toml" ]; then
              common+=(--config ".gitleaks.toml")
            fi
            if [ -f ".gitleaks-baseline.json" ]; then
              common+=(--baseline-path ".gitleaks-baseline.json")
            fi

            # History pass: catches a credential that was committed and later
            # removed, which a worktree scan can no longer see.
            gitleaks git "''${common[@]}" .

            # Worktree pass: `gitleaks git` walks superproject history, where the
            # secrets/ submodule is a gitlink and its blobs are absent, so a
            # credential committed inside that submodule was scanned by nothing.
            # `gitleaks dir` reads the filesystem, so the submodule is in scope.
            exec gitleaks dir "''${common[@]}" .
          '';
      };
    };
}
