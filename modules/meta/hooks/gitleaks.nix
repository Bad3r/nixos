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

            # Baselines are per scan mode. A git-scan fingerprint is
            # <commit>:<file>:<rule>:<line> and a dir-scan fingerprint is
            # <file>:<rule>:<line>, so sharing one file leaves the dir pass with
            # no suppression channel at all: every entry in
            # .gitleaks-baseline.json carries the commit form and can never match
            # a worktree finding. Generate the dir one with
            # `gitleaks dir --report-path` when a finding first needs recording.
            git_args=("''${common[@]}")
            if [ -f ".gitleaks-baseline.json" ]; then
              git_args+=(--baseline-path ".gitleaks-baseline.json")
            fi
            dir_args=("''${common[@]}")
            if [ -f ".gitleaks-baseline-dir.json" ]; then
              dir_args+=(--baseline-path ".gitleaks-baseline-dir.json")
            fi

            # History pass: catches a credential that was committed and later
            # removed, which a worktree scan can no longer see.
            gitleaks git "''${git_args[@]}" .

            # Worktree pass: `gitleaks git` walks superproject history, where the
            # secrets/ submodule is a gitlink and its blobs are absent, so a
            # credential committed inside that submodule was scanned by nothing.
            # `gitleaks dir` reads the filesystem, so the submodule is in scope.
            exec gitleaks dir "''${dir_args[@]}" .
          '';
      };
    };
}
