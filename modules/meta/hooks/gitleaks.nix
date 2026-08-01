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

            # One baseline per pass, because fingerprints are per scan mode and
            # per repository: a git-scan fingerprint is
            # <commit>:<file>:<rule>:<line> against that repo's shas, a dir-scan
            # fingerprint is <file>:<rule>:<line>. Sharing one file would leave
            # the other passes unable to suppress anything. Record a new entry
            # with the same flags this hook uses, --redact included:
            #   gitleaks dir --no-banner --redact --config .gitleaks.toml \
            #     --report-path .gitleaks-baseline-dir.json .
            # Matching is by fingerprint, so a raw baseline would still suppress,
            # but it commits the credential in plaintext.
            git_args=("''${common[@]}")
            if [ -f ".gitleaks-baseline.json" ]; then
              git_args+=(--baseline-path ".gitleaks-baseline.json")
            fi
            dir_args=("''${common[@]}")
            if [ -f ".gitleaks-baseline-dir.json" ]; then
              dir_args+=(--baseline-path ".gitleaks-baseline-dir.json")
            fi
            sub_args=("''${common[@]}")
            if [ -f ".gitleaks-baseline-secrets.json" ]; then
              sub_args+=(--baseline-path ".gitleaks-baseline-secrets.json")
            fi

            # writeShellApplication prepends set -e, so without collecting the
            # statuses the first pass to report a finding aborts the script and
            # the rest never run: a tree with both a superproject and a submodule
            # finding would take one push attempt per pass, each showing a third
            # of the problem.
            status=0

            # History pass: catches a credential that was committed and later
            # removed, which a worktree scan can no longer see.
            gitleaks git "''${git_args[@]}" . || status=1

            # Worktree pass: `gitleaks git` walks superproject history, where the
            # secrets/ submodule is a gitlink and its blobs are absent, so a
            # credential committed inside that submodule was scanned by nothing.
            # `gitleaks dir` reads the filesystem, so the submodule is in scope.
            gitleaks dir "''${dir_args[@]}" . || status=1

            # Submodule history: the argument for the first pass applies to the
            # one tree it cannot reach. The superproject sees only the gitlink
            # and the worktree pass sees only the submodule's current files, so a
            # credential committed inside secrets/ and later removed there is
            # covered by neither. Guarded because the submodule may not be
            # checked out; .git is a file there, not a directory, so -e not -d.
            if [ -e "secrets/.git" ]; then
              # git exports GIT_DIR to its hooks and gitleaks shells out to git,
              # so an inherited GIT_DIR overrides the path argument and silently
              # rescans the superproject instead. Caught by pre-push: with
              # GIT_DIR set to this linked worktree's git dir the pass reported
              # 2971 superproject commits rather than the submodule's 51.
              (
                unset GIT_DIR GIT_WORK_TREE
                gitleaks git "''${sub_args[@]}" secrets
              ) || status=1
            fi

            exit "$status"
          '';
      };
    };
}
