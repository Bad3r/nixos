# The refusal branches in hook-gitleaks are reachable from no other check:
# pre-commit.check.enable = false keeps the hook out of `checks`, and
# check.yml's gitleaks-scan exercises exactly one path, a full clone with
# secrets/ absent and no ignore file. Since that job made this hook the only
# credential gate on the merge path, a branch that stops refusing produces a
# green check rather than an eval error, which is the failure every guard here
# was added to prevent.
#
# Unlike gitleaks-allowlist-scope this cannot throw at eval: the branches are
# shell, so proving them needs the built hook run against real repositories.
# check-compliance forces drvPaths and never builds check outputs, so this
# derivation is built explicitly by the gitleaks-scan job. Adding it to `checks`
# alone would assert nothing.
_: {
  perSystem =
    { config, pkgs, ... }:
    {
      checks.hook-gitleaks-guards =
        pkgs.runCommandLocal "hook-gitleaks-guards"
          {
            nativeBuildInputs = [
              pkgs.git
              # Recording a baseline fixture needs gitleaks directly; the hook's
              # writeShellApplication wrapper puts it on its own PATH, not the
              # builder's.
              pkgs.gitleaks
              config.packages.hook-gitleaks
            ];
          }
          ''
            set -euo pipefail

            export HOME="$PWD/home"
            mkdir -p "$HOME"
            export GIT_CONFIG_GLOBAL="$HOME/gitconfig"
            : > "$GIT_CONFIG_GLOBAL"
            export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@invalid
            export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@invalid

            work="$PWD/work"
            mkdir -p "$work"

            rc=0
            hook_out=""
            run_hook() {
              set +e
              hook_out=$(hook-gitleaks 2>&1)
              rc=$?
              set -e
            }

            fail() {
              echo "hook-gitleaks-guards: FAIL: $1" >&2
              echo "--- exit $rc, hook output ---" >&2
              printf '%s\n' "$hook_out" >&2
              exit 1
            }

            # A refusal must emit no gitleaks result line at all. "no leaks found"
            # and "leaks found: N" share that substring, so one test covers both:
            # the point of every refusal is that no verdict was reached.
            expect_refusal() {
              [ "$rc" -eq 1 ] || fail "$1: expected exit 1, got $rc"
              if printf '%s' "$hook_out" | grep -q 'leaks found'; then
                fail "$1: refusal still emitted a gitleaks result line"
              fi
              printf '%s' "$hook_out" | grep -q "$2" || fail "$1: refusal did not mention '$2'"
            }

            # The submodule refusal is reached only after the superproject pass has
            # legitimately scanned and reported, so it cannot claim zero result
            # lines. Counting them is the equivalent assertion: exactly one means the
            # superproject was read and the submodule pass produced no verdict.
            expect_refusal_after_superproject() {
              [ "$rc" -eq 1 ] || fail "$1: expected exit 1, got $rc"
              lines=$(printf '%s\n' "$hook_out" | grep -c 'leaks found' || true)
              [ "$lines" -eq 1 ] || fail "$1: expected 1 result line (superproject only), got $lines"
              printf '%s' "$hook_out" | grep -q "$2" || fail "$1: refusal did not mention '$2'"
            }

            expect_clean() {
              [ "$rc" -eq 0 ] || fail "$1: expected exit 0, got $rc"
              printf '%s' "$hook_out" | grep -q 'no leaks found' || fail "$1: no clean result line"
            }

            expect_finding() {
              [ "$rc" -eq 1 ] || fail "$1: expected exit 1, got $rc"
              printf '%s' "$hook_out" | grep -q 'leaks found:' || fail "$1: credential went undetected"
            }

            # Both managed configs, because the hook now refuses when either is
            # absent. The superproject one carries the anchored documentation
            # path; the submodule one carries no paths key, which fixture 13
            # relies on.
            write_config() {
              printf '[extend]\nuseDefault = true\n[[allowlists]]\ndescription = "docs"\npaths = ["^nixos-manual/"]\n' \
                > "$1/.gitleaks.toml"
              printf '[extend]\nuseDefault = true\n' > "$1/.gitleaks-secrets.toml"
            }

            # A repository the hook reports clean: config committed, one ordinary
            # file, nothing else.
            new_repo() {
              git init -q --initial-branch=main "$1"
              write_config "$1"
              echo ordinary > "$1/file.txt"
              git -C "$1" add -A
              git -C "$1" commit -qm "base"
            }

            echo "hook-gitleaks-guards: 1/14 missing .gitleaks.toml"
            new_repo "$work/no-config"
            git -C "$work/no-config" rm -q --cached .gitleaks.toml
            rm "$work/no-config/.gitleaks.toml"
            git -C "$work/no-config" commit -qm "drop config"
            cd "$work/no-config" && run_hook
            expect_refusal "missing .gitleaks.toml" 'gitleaks.toml is missing'

            echo "hook-gitleaks-guards: 2/14 .gitleaksignore at the repository root"
            new_repo "$work/ignore-root"
            touch "$work/ignore-root/.gitleaksignore"
            cd "$work/ignore-root" && run_hook
            expect_refusal "root .gitleaksignore" '\.gitleaksignore suppresses findings'

            # Discovery is source-relative, so this file would filter the submodule
            # pass while a root-only guard saw nothing. No submodule is needed to
            # reach the branch: it tests the path, not the checkout.
            echo "hook-gitleaks-guards: 3/14 .gitleaksignore inside secrets/"
            new_repo "$work/ignore-sub"
            mkdir -p "$work/ignore-sub/secrets"
            touch "$work/ignore-sub/secrets/.gitleaksignore"
            cd "$work/ignore-sub" && run_hook
            expect_refusal "secrets/.gitleaksignore" 'secrets/\.gitleaksignore suppresses findings'

            echo "hook-gitleaks-guards: 4/14 shallow superproject"
            new_repo "$work/deep"
            echo second > "$work/deep/second.txt"
            git -C "$work/deep" add -A
            git -C "$work/deep" commit -qm second
            git clone -q --depth 1 "file://$work/deep" "$work/shallow"
            cd "$work/shallow" && run_hook
            expect_refusal "shallow superproject" 'shallow superproject'

            # rev-list --all --count returns 1 here, so a lower bound of one commit
            # passes while the history stays hidden.
            echo "hook-gitleaks-guards: 5/14 shallow submodule at secrets/"
            git init -q --initial-branch=main "$work/subup"
            for n in 1 2 3; do
              echo "s$n" > "$work/subup/s$n.txt"
              git -C "$work/subup" add -A
              git -C "$work/subup" commit -qm "s$n"
            done
            new_repo "$work/shallow-sub"
            git -C "$work/shallow-sub" -c protocol.file.allow=always \
              submodule add -q --depth 1 "file://$work/subup" secrets
            git -C "$work/shallow-sub" commit -qm "add shallow submodule"
            cd "$work/shallow-sub" && run_hook
            expect_refusal_after_superproject "shallow submodule" \
              'incomplete history (commits=1, shallow=true)'

            # The hook must still detect, not merely refuse: every branch above
            # would pass on a hook that reported nothing. Assembled at build time so
            # the pattern never appears whole in this file, where the repository's
            # own scan would report it.
            # The trailing gitleaks:allow directive makes --ignore-gitleaks-allow
            # load-bearing: without that flag this line is suppressed with no config
            # edit, no fingerprint and no review. The flag is unconditional, so the
            # credential must still be reported.
            echo "hook-gitleaks-guards: 6/14 committed credential is still reported"
            new_repo "$work/leak"
            pat_prefix=ghp
            pat_body=A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8
            printf '%s_%s # gitleaks:allow\n' "$pat_prefix" "$pat_body" > "$work/leak/token.txt"
            git -C "$work/leak" add -A
            git -C "$work/leak" commit -qm "commit a credential"
            cd "$work/leak" && run_hook
            expect_finding "committed credential"
            # gitleaks-scan prints this output into a public job log, so no
            # secret may reach it. Measured on 8.30.1: the console carries
            # Finding and Secret only under -v, which this hook does not pass,
            # so dropping --redact alone changes nothing today and this asserts
            # the pair rather than the flag. It fires the moment -v is added
            # without --redact, which is the combination that would publish the
            # credential the scan just found.
            if printf '%s' "$hook_out" | grep -q "''${pat_prefix}_''${pat_body}"; then
              fail "committed credential: the secret reached the output, so --redact is not in effect"
            fi

            echo "hook-gitleaks-guards: 7/14 clean full clone"
            new_repo "$work/clean"
            cd "$work/clean" && run_hook
            expect_clean "clean repository"

            # Warned, not refused: CI never checks secrets/ out, so refusing would
            # fail gitleaks-scan on every run. The warning is the only thing keeping
            # a partial run from reading as full coverage.
            echo "hook-gitleaks-guards: 8/14 absent submodule warns and still scans"
            new_repo "$work/absent"
            git -C "$work/absent" update-index --add \
              --cacheinfo 160000,0000000000000000000000000000000000000001,secrets
            git -C "$work/absent" commit -qm "record a gitlink"
            cd "$work/absent" && run_hook
            expect_clean "absent submodule"
            printf '%s' "$hook_out" | grep -q 'secrets/ is not checked out' \
              || fail "absent submodule: skipped silently"

            # The submodule pass itself, which nothing above reaches: fixture 5
            # refuses before `gitleaks git secrets` runs, fixture 8 takes the else
            # arm, and the rest carry no gitlink. secrets/ is absent in
            # gitleaks-scan too, so this is the only place the sub_args wiring, the
            # five unsets and the scan itself are exercised.
            echo "hook-gitleaks-guards: 9/14 credential inside a full-depth submodule"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/subup/token.txt"
            git -C "$work/subup" add -A
            git -C "$work/subup" commit -qm "commit a credential in the submodule"
            new_repo "$work/sub-leak"
            git -C "$work/sub-leak" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup" secrets
            git -C "$work/sub-leak" commit -qm "add submodule"
            cd "$work/sub-leak"
            # All five, because only the ones actually present in the environment
            # are asserted: with GIT_DIR alone, deleting the other three from the
            # unset list leaves the suite green. GIT_COMMON_DIR is the one the
            # commit-count assertion cannot substitute for, since that assertion
            # runs inside the same subshell and inherits the same redirect, so
            # rev-list reads the superproject's refs, returns a large non-zero
            # count with shallow=false, and passes while the scan reads nothing.
            # Exported rather than synthesised another way because git hands
            # GIT_DIR to its hooks, which is the environment pre-push runs in.
            export GIT_DIR="$work/sub-leak/.git" GIT_WORK_TREE="$work/sub-leak" \
              GIT_COMMON_DIR="$work/sub-leak/.git" \
              GIT_OBJECT_DIRECTORY="$work/sub-leak/.git/objects" \
              GIT_ALTERNATE_OBJECT_DIRECTORIES="$work/sub-leak/.git/objects"
            run_hook
            unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR \
              GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
            # The superproject pass sees only the gitlink, so a "leaks found:" line
            # can only have come from the submodule pass.
            expect_finding "submodule credential"

            # Both passes report in one run, which is the only thing that
            # exercises the `|| status=1` collection. writeShellApplication
            # prepends set -e, so without it the superproject finding aborts the
            # script and secrets/ is never scanned. Every other fixture carries a
            # finding in at most one pass, so that regression still exits 1 and
            # leaves them all green while the run covers one repository and
            # reports half the problem.
            echo "hook-gitleaks-guards: 10/14 both passes report in one run"
            new_repo "$work/both-leak"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/both-leak/token.txt"
            git -C "$work/both-leak" add -A
            git -C "$work/both-leak" commit -qm "commit a credential"
            git -C "$work/both-leak" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup" secrets
            git -C "$work/both-leak" commit -qm "add submodule"
            cd "$work/both-leak" && run_hook
            expect_finding "both passes"
            lines=$(printf '%s\n' "$hook_out" | grep -c 'leaks found:' || true)
            [ "$lines" -eq 2 ] || fail "both passes: expected 2 result lines, got $lines"

            # Fixture 1 covers the config file being absent; nothing covered the
            # --config flag being absent. write_config emits only
            # `[extend] useDefault = true`, which behaves exactly like the
            # built-in defaults, so dropping the flag leaves every fixture above
            # green while both passes scan unreviewed.
            #
            # The credential is planted in the submodule, not the superproject,
            # because without --config gitleaks resolves a config per source and
            # the superproject's source is the repository root, where it finds
            # the same .gitleaks.toml and behaves identically. The submodule
            # pass's source is secrets/, which holds no config, so it falls back
            # to the built-in defaults and reports the credential
            # .gitleaks-secrets.toml allowlists. A clean result therefore proves
            # that config reached a pass that could not have discovered it.
            echo "hook-gitleaks-guards: 11/14 the repository config reaches both passes"
            new_repo "$work/configured"
            # Both configs: .gitleaks-secrets.toml is what must reach the
            # submodule pass, and it is also an ordinary committed file that the
            # superproject pass scans, so without the same entry in
            # .gitleaks.toml the literal written here is itself reported.
            for cfg in .gitleaks.toml .gitleaks-secrets.toml; do
              printf '[[allowlists]]\ndescription = "fixture"\nregexes = ["%s_%s"]\n' \
                "$pat_prefix" "$pat_body" >> "$work/configured/$cfg"
            done
            git -C "$work/configured" add -A
            git -C "$work/configured" commit -qm "allowlist the submodule credential"
            git -C "$work/configured" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup" secrets
            git -C "$work/configured" commit -qm "add submodule carrying the credential"
            cd "$work/configured" && run_hook
            expect_clean "config in effect"

            # The sub_args baseline branch, which fixture 9 does not reach: it
            # carries no secrets/.gitleaks-baseline.json, and gitleaks-scan never
            # checks secrets/ out, so this suite is that branch's only reachable
            # caller. The announcement is asserted alongside it, because a pass
            # that filtered findings otherwise prints the same "no leaks found"
            # as one that filtered none, and for this pass the filtering list is
            # reviewed only in the private repository.
            echo "hook-gitleaks-guards: 12/14 submodule baseline filters and says so"
            new_repo "$work/sub-baselined"
            git -C "$work/sub-baselined" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup" secrets
            git -C "$work/sub-baselined" commit -qm "add submodule carrying the credential"
            gitleaks git --no-banner --redact --ignore-gitleaks-allow \
              --config "$work/sub-baselined/.gitleaks-secrets.toml" \
              --report-path "$work/sub-baselined/secrets/.gitleaks-baseline.json" \
              "$work/sub-baselined/secrets" || true
            cd "$work/sub-baselined" && run_hook
            expect_clean "submodule baseline"
            printf '%s' "$hook_out" | grep -q 'submodule pass filtered by' \
              || fail "submodule baseline: filtering was not announced"

            # The superproject's path allowlist must not reach the submodule's
            # path space. A paths pattern is matched against a File rooted at the
            # tree being scanned, and for `gitleaks git secrets` that root is the
            # submodule: File comes back as "nixos-manual/leak.txt", so a shared
            # config would skip a top-level nixos-manual/ inside the private
            # repository before scanning it, reachable by creating a directory
            # and invisible from here.
            echo "hook-gitleaks-guards: 13/14 superproject paths do not reach the submodule"
            git init -q --initial-branch=main "$work/docs-sub"
            mkdir -p "$work/docs-sub/nixos-manual"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/docs-sub/nixos-manual/leak.txt"
            git -C "$work/docs-sub" add -A
            git -C "$work/docs-sub" commit -qm "credential under a documentation path"
            new_repo "$work/path-scoped"
            git -C "$work/path-scoped" -c protocol.file.allow=always \
              submodule add -q "file://$work/docs-sub" secrets
            git -C "$work/path-scoped" commit -qm "add submodule"
            cd "$work/path-scoped" && run_hook
            expect_finding "submodule path scope"

            # The superproject half of the same pair. Dropping the baseline flag
            # is caught elsewhere, because the committed .gitleaks-baseline.json
            # has seven entries and gitleaks-scan fails without it, but nothing
            # caught dropping the announcement beside it: no other fixture
            # creates a repo-root baseline, so a superproject pass that filtered
            # findings printed the same "no leaks found" as one that filtered
            # none.
            echo "hook-gitleaks-guards: 14/14 superproject baseline filters and says so"
            new_repo "$work/baselined"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/baselined/token.txt"
            git -C "$work/baselined" add -A
            git -C "$work/baselined" commit -qm "commit a credential"
            gitleaks git --no-banner --redact --ignore-gitleaks-allow \
              --config "$work/baselined/.gitleaks.toml" \
              --report-path "$work/baselined/.gitleaks-baseline.json" \
              "$work/baselined" || true
            cd "$work/baselined" && run_hook
            expect_clean "superproject baseline"
            printf '%s' "$hook_out" | grep -q 'superproject pass filtered by' \
              || fail "superproject baseline: filtering was not announced"

            echo "hook-gitleaks-guards: all 14 fixtures passed"
            touch $out
          '';
    };
}
