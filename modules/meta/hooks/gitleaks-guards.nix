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
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      managedConfigNames = lib.filter (n: lib.hasPrefix ".gitleaks" n && lib.hasSuffix ".toml" n) (
        lib.attrNames config.files.file
      );
    in
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
              [ "$rc" -ne 0 ] || fail "$1: expected a nonzero exit, got $rc"
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

            # The source contract check quantifies over generated files, while
            # the hook selects configs through shell literals. Keep the two
            # directions load-bearing: a generated config with a contract must
            # reach a --config branch or it would read as reviewed while
            # governing no scan.
            hook_selections=$(
              grep -v '^[[:space:]]*#' ${config.packages.hook-gitleaks}/bin/hook-gitleaks \
                | grep -E -- '--config|_config=' || true
            )
            for cfg in ${lib.escapeShellArgs managedConfigNames}; do
              printf '%s\n' "$hook_selections" | grep -qF -- "$cfg" \
                || fail "managed config $cfg is generated but never reaches a --config branch"
            done

            # The converse direction: every config the hook actually selects
            # must be one gitleaks-allowlist-scope judges. The loop above only
            # quantifies over generated files, so a hardcoded --config naming
            # an ungenerated file passes it, passes unjudgedSources (which
            # also quantifies over config.files.file, not over the hook), and
            # ships a scan governed by a config where paths, regexes,
            # regexTarget, targetRules, stopwords, commits, [extend] and
            # [[rules]] are all unbounded.
            hook_configs=$(
              grep -v '^[[:space:]]*#' ${config.packages.hook-gitleaks}/bin/hook-gitleaks \
                | grep -oE '\.gitleaks[A-Za-z0-9._-]*\.toml' | sort -u
            )
            for cfg in $hook_configs; do
              printf '%s\n' ${lib.escapeShellArgs managedConfigNames} | grep -qFx -- "$cfg" \
                || fail "hook selects $cfg, which no source contract in gitleaks-allowlist-scope judges"
            done

            # The configs that actually ship, not a stand-in. gitleaks-allowlist-scope
            # can only pin the config text, and states so: the KV entry's
            # targetRules exists against a vector triggered by file content,
            # which no static check can reach. This suite runs real gitleaks
            # over real repositories, so it is the only place that behaviour is
            # reachable at all, and a stand-in config left it asserted by
            # nothing.
            write_config() {
              printf '%s' ${lib.escapeShellArg config.files.file.".gitleaks.toml".text} \
                > "$1/.gitleaks.toml"
              printf '%s' ${lib.escapeShellArg config.files.file.".gitleaks-secrets.toml".text} \
                > "$1/.gitleaks-secrets.toml"
              printf '%s' ${lib.escapeShellArg config.files.file.".gitleaks-gitlink.toml".text} \
                > "$1/.gitleaks-gitlink.toml"
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

            echo "hook-gitleaks-guards: 1/25 missing .gitleaks.toml"
            new_repo "$work/no-config"
            git -C "$work/no-config" rm -q --cached .gitleaks.toml
            rm "$work/no-config/.gitleaks.toml"
            git -C "$work/no-config" commit -qm "drop config"
            cd "$work/no-config" && run_hook
            expect_refusal "missing .gitleaks.toml" 'gitleaks.toml is missing'

            # The second iteration of the same loop, which fixture 1 never
            # reaches because it refuses on .gitleaks.toml first. Not covered by
            # gitleaks erroring on a missing --config either: in the state CI
            # runs in, secrets/ is absent and the submodule pass never executes,
            # so the job stays green while the config governing the private
            # submodule's scan is gone from the tree.
            echo "hook-gitleaks-guards: 2/25 missing .gitleaks-secrets.toml"
            new_repo "$work/no-sub-config"
            git -C "$work/no-sub-config" rm -q --cached .gitleaks-secrets.toml
            rm "$work/no-sub-config/.gitleaks-secrets.toml"
            git -C "$work/no-sub-config" commit -qm "drop submodule config"
            cd "$work/no-sub-config" && run_hook
            expect_refusal "missing .gitleaks-secrets.toml" 'gitleaks-secrets.toml is missing'

            echo "hook-gitleaks-guards: 3/25 missing .gitleaks-gitlink.toml"
            new_repo "$work/no-gitlink-config"
            git -C "$work/no-gitlink-config" rm -q --cached .gitleaks-gitlink.toml
            rm "$work/no-gitlink-config/.gitleaks-gitlink.toml"
            git -C "$work/no-gitlink-config" commit -qm "drop generic gitlink config"
            cd "$work/no-gitlink-config" && run_hook
            expect_refusal "missing .gitleaks-gitlink.toml" 'gitleaks-gitlink.toml is missing'

            echo "hook-gitleaks-guards: 4/25 .gitleaksignore at the repository root"
            new_repo "$work/ignore-root"
            touch "$work/ignore-root/.gitleaksignore"
            cd "$work/ignore-root" && run_hook
            expect_refusal "root .gitleaksignore" '\.gitleaksignore suppresses findings'

            # Discovery is source-relative, so this file would filter the
            # submodule pass while a root-only guard saw nothing. The guarded
            # roots come from the index now, so the fixture records a gitlink:
            # a .gitleaksignore beside a plain directory is read by no pass and
            # guarding it would be guarding nothing. No checkout is needed, since
            # the branch tests the path rather than the clone.
            echo "hook-gitleaks-guards: 5/25 .gitleaksignore inside a submodule root"
            new_repo "$work/ignore-sub"
            git -C "$work/ignore-sub" update-index --add \
              --cacheinfo 160000,0000000000000000000000000000000000000001,secrets
            git -C "$work/ignore-sub" commit -qm "record a gitlink"
            mkdir -p "$work/ignore-sub/secrets"
            touch "$work/ignore-sub/secrets/.gitleaksignore"
            cd "$work/ignore-sub" && run_hook
            expect_refusal "secrets/.gitleaksignore" 'secrets/\.gitleaksignore suppresses findings'

            echo "hook-gitleaks-guards: 6/25 shallow superproject"
            new_repo "$work/deep"
            echo second > "$work/deep/second.txt"
            git -C "$work/deep" add -A
            git -C "$work/deep" commit -qm second
            git clone -q --depth 1 "file://$work/deep" "$work/shallow"
            cd "$work/shallow" && run_hook
            expect_refusal "shallow superproject" \
              'incomplete history (commits=1, shallow=true)'

            # rev-list --all --count returns 1 here, so a lower bound of one commit
            # passes while the history stays hidden.
            echo "hook-gitleaks-guards: 7/25 shallow submodule at secrets/"
            # A second, credential-free upstream for fixtures that need a clean
            # first submodule; subup gains a credential in fixture 10.
            git init -q --initial-branch=main "$work/subup-clean"
            echo clean > "$work/subup-clean/ok.txt"
            git -C "$work/subup-clean" add -A
            git -C "$work/subup-clean" commit -qm clean
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
            echo "hook-gitleaks-guards: 8/25 committed credential is still reported"
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

            echo "hook-gitleaks-guards: 9/25 clean full clone"
            new_repo "$work/clean"
            cd "$work/clean" && run_hook
            expect_clean "clean repository"

            # Warned, not refused: CI never checks secrets/ out, so refusing would
            # fail gitleaks-scan on every run. The warning is the only thing keeping
            # a partial run from reading as full coverage.
            echo "hook-gitleaks-guards: 10/25 absent submodule warns and still scans"
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
            # six unsets and the scan itself are exercised.
            echo "hook-gitleaks-guards: 11/25 credential inside a full-depth submodule"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/subup/token.txt"
            git -C "$work/subup" add -A
            git -C "$work/subup" commit -qm "commit a credential in the submodule"
            new_repo "$work/sub-leak"
            git -C "$work/sub-leak" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup" secrets
            git -C "$work/sub-leak" commit -qm "add submodule"
            cd "$work/sub-leak"
            # All six, because only the ones actually present in the environment
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
              GIT_ALTERNATE_OBJECT_DIRECTORIES="$work/sub-leak/.git/objects" \
              GIT_INDEX_FILE="$work/sub-leak/.git/index"
            run_hook
            unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR \
              GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
              GIT_INDEX_FILE
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
            echo "hook-gitleaks-guards: 12/25 both passes report in one run"
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
            echo "hook-gitleaks-guards: 13/25 the repository config reaches both passes"
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
            echo "hook-gitleaks-guards: 14/25 submodule baseline filters and says so"
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
            echo "hook-gitleaks-guards: 15/25 superproject paths do not reach the submodule"
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

            # The baseline flag and its announcement are both load-bearing here.
            # Without the flag the planted credential remains, while without the
            # announcement a filtered result is indistinguishable from a clean
            # scan in the hook output.
            echo "hook-gitleaks-guards: 16/25 superproject baseline filters and says so"
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

            # The other half of the superproject assertion. is-shallow-repository
            # reports false on a repository with no reachable commits, so the
            # count is what separates "read the history" from "read nothing":
            # GIT_COMMON_DIR or GIT_OBJECT_DIRECTORY pointed away from the
            # repository produces the same 0 commits, and this pass runs in the
            # ambient environment where those live.
            echo "hook-gitleaks-guards: 17/25 superproject with no commits"
            git init -q --initial-branch=main "$work/no-commits"
            write_config "$work/no-commits"
            cd "$work/no-commits" && run_hook
            expect_refusal "empty superproject" 'incomplete history (commits=0, shallow=false)'

            # The KV allowlist's targetRules, which gitleaks-allowlist-scope
            # pins in config text and explicitly cannot verify: the vector is
            # triggered by file content, so only a real scan reaches it. The
            # note belongs in the private submodule, which is the only pass
            # governed by .gitleaks-secrets.toml. Two lines, one carrying the KV
            # note alone and one carrying a Stripe live key followed by the same
            # note. The first must be suppressed, which is what the entry exists
            # for; the second must still be reported, which is what targetRules =
            # ["generic-api-key"] buys. Without it the line-target match drops
            # every rule's finding on that line and the Stripe key disappears.
            echo "hook-gitleaks-guards: 18/25 the KV allowlist suppresses only its own rule"
            new_repo "$work/kv-scope"
            git init -q --initial-branch=main "$work/kv-sub"
            kv_note='# production'
            kv_note+=" keys"
            kv_value_start=0123456789abcdef
            kv_value_end=0123456789abcdef
            kv_note+=" KV: $kv_value_start$kv_value_end"
            stripe_prefix=sk_live
            stripe_body=4eC39HqLyjWDarjtT1zdp7dc
            printf '%s\n' "$kv_note" > "$work/kv-sub/notes.md"
            printf '%s_%s %s\n' "$stripe_prefix" "$stripe_body" "$kv_note" \
              >> "$work/kv-sub/notes.md"
            git -C "$work/kv-sub" add -A
            git -C "$work/kv-sub" commit -qm "kv note, and a live key sharing a line with one"
            git -C "$work/kv-scope" -c protocol.file.allow=always \
              submodule add -q "file://$work/kv-sub" secrets
            git -C "$work/kv-scope" commit -qm "add private operational note"
            cd "$work/kv-scope" && run_hook
            expect_finding "kv target scope"
            printf '%s' "$hook_out" | grep -q 'leaks found: 1' \
              || fail "kv target scope: expected exactly one finding, the Stripe key"

            # Additional gitlinks, which is the whole point of deriving the list:
            # with secrets/ hardcoded these repositories were scanned by neither
            # pass and the run still printed "no leaks found" and exited 0. Both
            # the non-ASCII and the space-containing path carry a credential, and
            # the non-ASCII repository carries a nested gitlink too. The count is
            # asserted rather than the presence of one: with a single planted
            # credential a parser that mangles another path drops it into the
            # not-checked-out warning and the run still exits 1 on the remaining
            # finding, leaving the regression invisible.
            echo "hook-gitleaks-guards: 19/25 every gitlink is scanned, not just the first"
            git init -q --initial-branch=main "$work/second-up"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/second-up/tok.txt"
            other_kv_note='# production'
            other_kv_note+=" keys"
            other_kv_value_start=0123456789abcdef
            other_kv_value_end=0123456789abcdef
            other_kv_note+=" KV: $other_kv_value_start$other_kv_value_end"
            printf '%s\n' "$other_kv_note" > "$work/second-up/kv.txt"
            git init -q --initial-branch=main "$work/nested-up"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/nested-up/nested-tok.txt"
            git -C "$work/nested-up" add -A
            git -C "$work/nested-up" commit -qm "credential in the nested gitlink"
            git -C "$work/second-up" -c protocol.file.allow=always \
              submodule add -q "file://$work/nested-up" "nested with space"
            git -C "$work/second-up" add -A
            git -C "$work/second-up" commit -qm "credential in the nested gitlink parent"
            git init -q --initial-branch=main "$work/space-up"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/space-up/tok.txt"
            printf '%s\n' "$other_kv_note" > "$work/space-up/kv.txt"
            git -C "$work/space-up" add -A
            git -C "$work/space-up" commit -qm "credential in the space-containing submodule"
            new_repo "$work/two-subs"
            unicode_path=$(printf 'vendeur-\303\251')
            git -C "$work/two-subs" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup-clean" secrets
            git -C "$work/two-subs" -c protocol.file.allow=always \
              submodule add -q "file://$work/second-up" "$unicode_path"
            git -C "$work/two-subs" -c protocol.file.allow=always \
              submodule update -q --init --recursive -- "$unicode_path"
            git -C "$work/two-subs" -c protocol.file.allow=always \
              submodule add -q "file://$work/space-up" "vendor with space"
            git -C "$work/two-subs" commit -qm "two submodules"
            cd "$work/two-subs" && run_hook
            expect_finding "second submodule"
            lines=$(printf '%s\n' "$hook_out" | grep -c 'leaks found:' || true)
            [ "$lines" -eq 3 ] || fail "second submodule: expected 3 result lines, got $lines"
            printf '%s' "$hook_out" | grep -q 'leaks found: 1' \
              || fail "nested gitlink: expected a separate finding result"
            printf '%s' "$hook_out" | grep -q 'leaks found: 2' \
              || fail "generic gitlink config: the second submodule KV note was suppressed"

            echo "hook-gitleaks-guards: 20/25 readable wrong index is ignored"
            new_repo "$work/wrong-index"
            git -C "$work/wrong-index" -c protocol.file.allow=always \
              submodule add -q "file://$work/subup" secrets
            git -C "$work/wrong-index" commit -qm "add credential submodule"
            new_repo "$work/decoy-index"
            export GIT_INDEX_FILE="$work/decoy-index/.git/index"
            cd "$work/wrong-index" && run_hook
            unset GIT_INDEX_FILE
            expect_finding "readable wrong index"

            echo "hook-gitleaks-guards: 21/25 unreadable index refuses before enumeration"
            new_repo "$work/broken-index"
            mv "$work/broken-index/.git/index" "$work/broken-index/.git/index.saved"
            mkdir "$work/broken-index/.git/index"
            cd "$work/broken-index" && run_hook
            expect_refusal "unreadable index" 'cannot read the index'

            echo "hook-gitleaks-guards: 22/25 valid alternate GIT_DIR is ignored"
            new_repo "$work/ambient-git-dir"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/ambient-git-dir/token.txt"
            git -C "$work/ambient-git-dir" add -A
            git -C "$work/ambient-git-dir" commit -qm "commit a credential"
            new_repo "$work/decoy-git-dir"
            export GIT_DIR="$work/decoy-git-dir/.git" \
              GIT_WORK_TREE="$work/decoy-git-dir"
            cd "$work/ambient-git-dir" && run_hook
            unset GIT_DIR GIT_WORK_TREE
            expect_finding "valid alternate GIT_DIR"

            # The superproject's baseline announcement is now built after the
            # enumeration, ignore and history guards rather than before them,
            # so a refusal from any of the three cannot be preceded by a claim
            # that a scan ran and was filtered. Shallow after a committed
            # baseline is the reachable shape: this repository carries
            # .gitleaks-baseline.json today, so any shallow checkout hits
            # exactly this combination.
            echo "hook-gitleaks-guards: 23/25 baseline announcement does not precede a refusal"
            new_repo "$work/baseline-then-shallow"
            echo second > "$work/baseline-then-shallow/second.txt"
            git -C "$work/baseline-then-shallow" add -A
            git -C "$work/baseline-then-shallow" commit -qm second
            printf '[]' > "$work/baseline-then-shallow/.gitleaks-baseline.json"
            git -C "$work/baseline-then-shallow" add -A
            git -C "$work/baseline-then-shallow" commit -qm "record an empty baseline"
            git clone -q --depth 1 "file://$work/baseline-then-shallow" "$work/baseline-then-shallow-clone"
            cd "$work/baseline-then-shallow-clone" && run_hook
            expect_refusal "baseline announcement ordering" 'incomplete history (commits=1, shallow=true)'
            if printf '%s' "$hook_out" | grep -q 'filtered by .gitleaks-baseline.json'; then
              fail "baseline announcement ordering: announced a filtered scan before refusing to run one at all"
            fi

            # The gitlink half of the same fix. A dedicated upstream rather than
            # $work/subup, which fixtures 11 through 14 also submodule-add: a
            # baseline file committed into it here would reach their clones too
            # and change what those fixtures are testing.
            echo "hook-gitleaks-guards: 24/25 gitlink baseline announcement does not precede a refusal"
            git init -q --initial-branch=main "$work/gitlink-baseline-up"
            echo one > "$work/gitlink-baseline-up/one.txt"
            git -C "$work/gitlink-baseline-up" add -A
            git -C "$work/gitlink-baseline-up" commit -qm one
            echo two > "$work/gitlink-baseline-up/two.txt"
            git -C "$work/gitlink-baseline-up" add -A
            git -C "$work/gitlink-baseline-up" commit -qm two
            printf '[]' > "$work/gitlink-baseline-up/.gitleaks-baseline.json"
            git -C "$work/gitlink-baseline-up" add -A
            git -C "$work/gitlink-baseline-up" commit -qm "record an empty baseline"
            new_repo "$work/gitlink-baseline-shallow"
            git -C "$work/gitlink-baseline-shallow" -c protocol.file.allow=always \
              submodule add -q --depth 1 "file://$work/gitlink-baseline-up" secrets
            git -C "$work/gitlink-baseline-shallow" commit -qm "add shallow submodule with a baseline"
            cd "$work/gitlink-baseline-shallow" && run_hook
            expect_refusal_after_superproject "gitlink baseline announcement ordering" \
              'incomplete history (commits=1, shallow=true)'
            if printf '%s' "$hook_out" | grep -q 'submodule pass filtered by'; then
              fail "gitlink baseline announcement ordering: announced a filtered scan before refusing to run one at all"
            fi

            # A gitlink path is a bare positional argument to the scan itself,
            # unlike every other use of $sm, which either binds to a flag
            # (git -C, [ -e ) or is pure string concatenation. update-index
            # rather than submodule add: git's own submodule subcommands warn
            # or refuse on a path that looks like an option, which is the
            # wrong layer to prove this at. Cloning straight into that path
            # reproduces the index state a genuine gitlink named this way
            # would have.
            echo "hook-gitleaks-guards: 25/25 gitlink named with a leading dash is still scanned"
            git init -q --initial-branch=main "$work/dash-up"
            printf '%s_%s\n' "$pat_prefix" "$pat_body" > "$work/dash-up/token.txt"
            git -C "$work/dash-up" add -A
            git -C "$work/dash-up" commit -qm "commit a credential"
            dash_sha=$(git -C "$work/dash-up" rev-parse HEAD)
            new_repo "$work/dash-gitlink"
            git -C "$work/dash-gitlink" update-index --add --cacheinfo "160000,$dash_sha,-v"
            git -C "$work/dash-gitlink" commit -qm "record a gitlink named -v"
            git -c protocol.file.allow=always clone -q "file://$work/dash-up" "$work/dash-gitlink/-v"
            cd "$work/dash-gitlink" && run_hook
            expect_finding "dash-prefixed gitlink"

            echo "hook-gitleaks-guards: all 25 fixtures passed"
            touch $out
          '';
    };
}
