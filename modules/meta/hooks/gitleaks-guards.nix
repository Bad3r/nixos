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

            write_config() {
              printf '[extend]\nuseDefault = true\n' > "$1/.gitleaks.toml"
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

            echo "hook-gitleaks-guards: 1/9 missing .gitleaks.toml"
            new_repo "$work/no-config"
            git -C "$work/no-config" rm -q --cached .gitleaks.toml
            rm "$work/no-config/.gitleaks.toml"
            git -C "$work/no-config" commit -qm "drop config"
            cd "$work/no-config" && run_hook
            expect_refusal "missing .gitleaks.toml" 'gitleaks.toml is missing'

            echo "hook-gitleaks-guards: 2/9 .gitleaksignore at the repository root"
            new_repo "$work/ignore-root"
            touch "$work/ignore-root/.gitleaksignore"
            cd "$work/ignore-root" && run_hook
            expect_refusal "root .gitleaksignore" '\.gitleaksignore suppresses findings'

            # Discovery is source-relative, so this file would filter the submodule
            # pass while a root-only guard saw nothing. No submodule is needed to
            # reach the branch: it tests the path, not the checkout.
            echo "hook-gitleaks-guards: 3/9 .gitleaksignore inside secrets/"
            new_repo "$work/ignore-sub"
            mkdir -p "$work/ignore-sub/secrets"
            touch "$work/ignore-sub/secrets/.gitleaksignore"
            cd "$work/ignore-sub" && run_hook
            expect_refusal "secrets/.gitleaksignore" 'secrets/\.gitleaksignore suppresses findings'

            echo "hook-gitleaks-guards: 4/9 shallow superproject"
            new_repo "$work/deep"
            echo second > "$work/deep/second.txt"
            git -C "$work/deep" add -A
            git -C "$work/deep" commit -qm second
            git clone -q --depth 1 "file://$work/deep" "$work/shallow"
            cd "$work/shallow" && run_hook
            expect_refusal "shallow superproject" 'shallow superproject'

            # rev-list --all --count returns 1 here, so a lower bound of one commit
            # passes while the history stays hidden.
            echo "hook-gitleaks-guards: 5/9 shallow submodule at secrets/"
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
            echo "hook-gitleaks-guards: 6/9 committed credential is still reported"
            new_repo "$work/leak"
            pat_prefix=ghp
            pat_body=A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8
            printf '%s_%s # gitleaks:allow\n' "$pat_prefix" "$pat_body" > "$work/leak/token.txt"
            git -C "$work/leak" add -A
            git -C "$work/leak" commit -qm "commit a credential"
            cd "$work/leak" && run_hook
            expect_finding "committed credential"

            echo "hook-gitleaks-guards: 7/9 clean full clone"
            new_repo "$work/clean"
            cd "$work/clean" && run_hook
            expect_clean "clean repository"

            # Warned, not refused: CI never checks secrets/ out, so refusing would
            # fail gitleaks-scan on every run. The warning is the only thing keeping
            # a partial run from reading as full coverage.
            echo "hook-gitleaks-guards: 8/9 absent submodule warns and still scans"
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
            echo "hook-gitleaks-guards: 9/9 credential inside a full-depth submodule"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/subup/token.txt"
            git -C "$work/subup" add -A
            git -C "$work/subup" commit -qm "commit a credential in the submodule"
            new_repo "$work/sub-leak"
            git -C "$work/sub-leak" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup" secrets
            git -C "$work/sub-leak" commit -qm "add submodule"
            cd "$work/sub-leak"
            # Exported, because git exports GIT_DIR to its hooks and that is how
            # the redirect reached this pass in the first place. With a clean
            # environment the five unsets are asserted by nothing: deleting them
            # leaves every fixture passing while the pass silently rescans the
            # superproject, counts its commits as the submodule's, and reports
            # secrets/ clean.
            export GIT_DIR="$work/sub-leak/.git" GIT_WORK_TREE="$work/sub-leak"
            run_hook
            unset GIT_DIR GIT_WORK_TREE
            # The superproject pass sees only the gitlink, so a "leaks found:" line
            # can only have come from the submodule pass.
            expect_finding "submodule credential"

            echo "hook-gitleaks-guards: all 9 fixtures passed"
            touch $out
          '';
    };
}
