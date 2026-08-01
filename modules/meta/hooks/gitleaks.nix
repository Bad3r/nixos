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

            # --ignore-gitleaks-allow: without it a trailing `gitleaks:allow`
            # comment on the leaking line drops that finding with no config edit
            # and no fingerprint, which sits outside every field
            # gitleaks-allowlist-scope pins and outside the baselines. Unused in
            # this repo, so disabling it costs nothing.
            common=(--no-banner --redact --ignore-gitleaks-allow)
            if [ -f ".gitleaks.toml" ]; then
              common+=(--config ".gitleaks.toml")
            fi

            # One baseline per pass, because fingerprints carry the shas of the
            # repository they came from, so the superproject's entries can never
            # match a submodule finding. Record a new entry with the same flags
            # this hook uses, --redact included:
            #   gitleaks git --no-banner --redact --ignore-gitleaks-allow \
            #     --config .gitleaks.toml \
            #     --report-path .gitleaks-baseline-secrets.json secrets
            # Matching is by fingerprint, so a raw baseline would still suppress,
            # but it commits the credential in plaintext.
            git_args=("''${common[@]}")
            if [ -f ".gitleaks-baseline.json" ]; then
              git_args+=(--baseline-path ".gitleaks-baseline.json")
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

            # .gitleaksignore is read from the repo root automatically and
            # suppresses by fingerprint exactly like the baselines below, but
            # with no flag and no review. Fail rather than let one appear
            # unnoticed alongside the channels this hook wires up deliberately.
            if [ -e ".gitleaksignore" ]; then
              echo "hook-gitleaks: .gitleaksignore suppresses findings outside the reviewed baselines; record them in .gitleaks-baseline.json or .gitleaks-baseline-secrets.json instead" >&2
              status=1
            fi

            # History pass: catches a credential that was committed and later
            # removed, which a worktree scan can no longer see.
            gitleaks git "''${git_args[@]}" . || status=1

            # Submodule history: the superproject pass sees only the gitlink, so
            # nothing here covered secrets/ before this. Deliberately git and not
            # a `gitleaks dir` filesystem walk: dir mode ignores .gitignore, and
            # the patterns this repo reserves for local plaintext (secrets/*.dec*
            # from a local sops -d, plus *.key, *.pem, *.agekey, .env, id_*) are
            # exactly what such a pass would uniquely add, so at pre-push it
            # would block every push during a normal decrypt. Everything being
            # pushed is committed, so the git passes already cover it. Guarded
            # because the submodule may not be checked out; .git is a file there,
            # not a directory, so -e not -d.
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
