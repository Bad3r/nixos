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

            # Every field gitleaks-allowlist-scope pins is a field of this file,
            # so scanning without it silently drops the whole reviewed ruleset:
            # both passes fall back to gitleaks' built-in defaults and still end
            # in "no leaks found" and exit 0. Dropping --config is also the one
            # condition under which gitleaks resolves a config per source, so
            # secrets/.gitleaks.toml would govern the submodule pass: verified
            # on 8.30.1 that a source-directory .gitleaks.toml suppresses a
            # finding the defaults report. That is a ruleset in the private
            # repository deciding what the public one reports, the same reach
            # the .gitleaksignore guard below refuses. write-files owns this
            # file, so its absence is a broken checkout, never a state to scan.
            # One config per pass, because a paths allowlist is matched against a
            # File rooted at the tree being scanned: for `gitleaks git secrets`
            # that root is the submodule, so File comes back as
            # "nixos-manual/leak.txt" and the superproject's anchored
            # "^nixos-manual/" would skip a top-level directory of that name
            # inside the private repository, before scanning it and invisibly
            # from here. .gitleaks-secrets.toml carries the content-scoped
            # allowlists and no paths key at all.
            for config_file in ".gitleaks.toml" ".gitleaks-secrets.toml"; do
              if [ ! -f "$config_file" ]; then
                echo "hook-gitleaks: $config_file is missing, so the ruleset gitleaks-allowlist-scope pins is not in effect and gitleaks would fall back to its built-in defaults and to per-source config discovery; regenerate it with 'nix develop --accept-flake-config -c write-files' instead of scanning unreviewed" >&2
                exit 1
              fi
            done

            # One baseline per pass, because fingerprints carry the shas of the
            # repository they came from, so the superproject's entries can never
            # match a submodule finding. The submodule's baseline lives inside
            # the submodule rather than here: a report entry carries File,
            # Commit, Link, Author, Email, Date and the full commit Message, and
            # --redact masks only Match and Secret, so recording a secrets/
            # finding in this repository would publish that private history's
            # metadata in a public one. Inside the submodule it is also reviewed
            # in the repository whose history it describes, and only present when
            # the submodule is checked out, which is already the pass's guard.
            # Record a new entry with the same flags this hook uses:
            #   gitleaks git --no-banner --redact --ignore-gitleaks-allow \
            #     --config .gitleaks.toml \
            #     --report-path .gitleaks-baseline.json .
            #   gitleaks git --no-banner --redact --ignore-gitleaks-allow \
            #     --config .gitleaks-secrets.toml \
            #     --report-path secrets/.gitleaks-baseline.json secrets
            # Matching is by fingerprint, so a raw baseline would still suppress,
            # but it commits the credential in plaintext. Dropping
            # --ignore-gitleaks-allow instead yields a baseline without the
            # fingerprint this hook reports, so the finding stays unsuppressable.
            # Announced, because a baseline is the one suppression channel this
            # hook keeps: a pass that filtered findings prints the same "no leaks
            # found" as one that filtered none, and for the submodule the list
            # doing the filtering lives in the private repository, so a reviewer
            # here cannot see what a clean result was measured against.
            git_args=("''${common[@]}" --config ".gitleaks.toml")
            if [ -f ".gitleaks-baseline.json" ]; then
              git_args+=(--baseline-path ".gitleaks-baseline.json")
              echo "hook-gitleaks: superproject pass filtered by .gitleaks-baseline.json" >&2
            fi

            # Derived from the index rather than naming secrets/, the one
            # enumeration left in this file after round 16 replaced the GIT_*
            # unsets with an assertion. A second gitlink was scanned by neither
            # pass, its .gitleaksignore was not refused, and the run still
            # printed "no leaks found" and exited 0: the silent partial coverage
            # the absent-checkout warning below exists to prevent, one level up.
            # With one gitlink today the behaviour is unchanged.
            tab=$'\t'
            mapfile -d "" -t index_entries < <(git ls-files -s -z)
            submodules=()
            for entry in "''${index_entries[@]}"; do
              case "$entry" in
                "160000 "*) submodules+=("''${entry#*"$tab"}") ;;
              esac
            done

            # writeShellApplication prepends set -e, so without collecting the
            # statuses the first pass to report a finding aborts the script and
            # the rest never run: a tree with both a superproject and a submodule
            # finding would take one push attempt per pass, each showing a third
            # of the problem.
            status=0

            # .gitleaksignore is read from the repo root automatically and
            # suppresses by fingerprint exactly like the baselines below, but
            # with no flag and no review. Refuse to scan at all rather than
            # report a result it has already filtered: unlike gitleaks:allow,
            # which --ignore-gitleaks-allow neutralises above, this channel
            # cannot be turned off. On 8.30.1 the repo-root file is honoured even
            # with --gitleaks-ignore-path pointed at an empty or nonexistent
            # directory, so continuing would print "no leaks found" for the very
            # findings the file hid.
            # Both roots, because discovery is source-relative rather than
            # flag-driven: a .gitleaksignore inside the scanned directory is
            # honoured, so secrets/.gitleaksignore would filter the submodule
            # pass while a root-only guard saw nothing. That is the private
            # repository, and it now also holds secrets/.gitleaks-baseline.json,
            # so a sibling ignore file there is the plausible shape.
            for ignore_file in ".gitleaksignore" "''${submodules[@]/%//.gitleaksignore}"; do
              if [ -e "$ignore_file" ]; then
                echo "hook-gitleaks: $ignore_file suppresses findings outside the reviewed baselines and cannot be disabled; remove it and record them in .gitleaks-baseline.json or the matching <submodule>/.gitleaks-baseline.json instead" >&2
                exit 1
              fi
            done

            # gitleaks git reads whatever the clone has, so a shallow
            # superproject scans only the fetched tip and exits 0 with "no
            # leaks found": the same vacuous green the submodule assertion
            # below guards against, on a cheaper trigger. The only thing
            # keeping the CI scan honest is fetch-depth: 0 in
            # .github/workflows/check.yml, which nothing verifies stays set,
            # and gitleaks-scan is the only credential gate on the merge path.
            # A --depth working copy does the same to every local pre-push.
            # The commit count as well as the shallow test, matching the
            # submodule assertion below. The count is the half that catches a
            # redirect: GIT_COMMON_DIR or GIT_OBJECT_DIRECTORY pointed away from
            # the repository yields "0 commits scanned", "no leaks found" and
            # exit 0 while is-shallow-repository still reports false. This pass
            # runs in the ambient environment, where those variables live, and
            # unlike the submodule pass it cannot unset them without also
            # redirecting itself, so the pass gitleaks-scan always runs had the
            # weaker precondition of the two.
            super_commits=$(git rev-list --all --count)
            super_shallow=$(git rev-parse --is-shallow-repository)
            if [ "$super_commits" -eq 0 ] || [ "$super_shallow" != "false" ]; then
              echo "hook-gitleaks: superproject pass would read an incomplete history (commits=$super_commits, shallow=$super_shallow); refusing to report the repository clean (run 'git fetch --unshallow' locally, or set fetch-depth: 0 on the checkout step in CI)" >&2
              exit 1
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
            for sm in "''${submodules[@]}"; do
            sub_args=("''${common[@]}" --config ".gitleaks-secrets.toml")
            if [ -f "$sm/.gitleaks-baseline.json" ]; then
              sub_args+=(--baseline-path "$sm/.gitleaks-baseline.json")
              echo "hook-gitleaks: submodule pass filtered by $sm/.gitleaks-baseline.json, reviewed only in the private repository" >&2
            fi
            if [ -e "$sm/.git" ]; then
              # git exports GIT_DIR to its hooks and gitleaks shells out to git,
              # so an inherited GIT_DIR overrides the path argument and silently
              # rescans the superproject instead. Caught by pre-push: with
              # GIT_DIR set to this linked worktree's git dir the pass reported
              # 2971 superproject commits rather than the submodule's 51. The
              # other four redirect git the same way and fail differently rather
              # than not at all: GIT_COMMON_DIR or GIT_OBJECT_DIRECTORY alone
              # yields 0 commits scanned and "no leaks found", a pass that
              # reports success without reading anything.
              (
                unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR \
                  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
                # Assert the pass reads the submodule's history rather than
                # trusting the enumeration above to be complete: any redirect it
                # misses, and an initialised-but-empty submodule, both end in
                # "0 commits scanned" and exit 0. Since gitleaks-scan made this
                # hook the only credential gate on the merge path, that would be
                # a green check over an unscanned repository. Shallow too, and
                # not because a count of zero implies it: clone
                # --shallow-submodules, and submodule.secrets.shallow in
                # .gitmodules or local config, each leave a one-commit clone
                # that satisfies any lower bound while hiding the other fifty.
                sub_commits=$(git -C "$sm" rev-list --all --count)
                sub_shallow=$(git -C "$sm" rev-parse --is-shallow-repository)
                if [ "$sub_commits" -eq 0 ] || [ "$sub_shallow" != "false" ]; then
                  echo "hook-gitleaks: submodule pass would read an incomplete history (commits=$sub_commits, shallow=$sub_shallow); refusing to report $sm/ clean (run 'git submodule update --init $sm', and 'git -C $sm fetch --unshallow' if it was cloned shallow)" >&2
                  exit 1
                fi
                gitleaks git "''${sub_args[@]}" "$sm"
              ) || status=1
            else
              # Say so rather than let a partial run read as full coverage: the
              # index records a gitlink at secrets/, so an absent checkout means
              # its history was not scanned, not that it is clean. Warned and not
              # refused because this is the state in CI, where gitleaks-scan
              # never checks the submodule out, and in every fresh
              # `git worktree add` tree, which this repo's workflow requires per
              # change.
              echo "hook-gitleaks: $sm/ is not checked out; its history was NOT scanned and this run covers the superproject only (run 'git submodule update --init $sm' to cover it)" >&2
            fi
            done

            exit "$status"
          '';
      };
    };
}
